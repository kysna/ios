#!/bin/bash 

export LC_ALL=C


retvalue=0
retvalue2=0

#napoveda
print_help() 
{
	echo "Usage: $0 [-vtrsc] TEST_DIR [REGEX]
    -v  validate tree
    -t  run tests
    -r  report results
    -s  synchronize expected results
    -c  clear generated files

    It is mandatory to supply at least one option." >&2;
	exit 2;
}




# zpracovani parametru
v=0;
t=0;
r=0;
s=0;
c=0;

#pokud fce nema parametr, vypise napovedu a skonci
if [ $# -le 0 ]; then
	print_help
fi


while getopts ":vtrsc" option; do

	case $option in
		v) v=1;;
		t) t=1;;
		r) r=1;;
		s) s=1;;
		c) c=1;;
		?) print_help;;
		   
	esac
done

if [ $v -eq 0 -a $t -eq 0 -a $r -eq 0 -a $s -eq 0 -a $c -eq 0 ]; then
	print_help
fi

#ziskani odkazu na strom a regex vyrazu
OPTIND=`expr $OPTIND - 1`;
shift $OPTIND
tree="$1";
regex="$2";


########### pomocne printy, vymazat
#echo "$tree $regex"
#echo "v:$v t:$t r:$r s:$s c:$c"
##########

if [ -z "$tree" ]; then
	echo "Nevalidni strom." >&2
	exit 2
fi

cd "$tree"
if [ $? -ne 0 ]; then
	retvalue=1
	echo "Doslo k chybe pri operaci cd, zadana slozka pravdepodobne neexistuje." >&2
fi

test_tree=`find . | grep -E "$regex"`
if [ -z "$test_tree" ]; then
	exit 0
fi


#prepinac v
if [ $v -eq 1 ]; then

	#############
	#pokud je v adresari slozka, pak jsou tam jen slozky
	
	#vytvor seznam kontrolovanych stringu
	a=`find . -type d | grep -E ".*$regex.*"`
	#na konec vloz zarazku
	b="$a .END"
	counter=1
	#vyber prvni string ze seznamu
	check=`echo $b | cut -d ' ' -f$counter`

	#provadej cyklus dokud nenarazis na zarazku
	while [ "$check" != ".END" ]; do
		#podivej se jestli jsou ve slozce podslozky
		slozky=`find "$check" -maxdepth 1 -type d`
		#pokud jsou tak se koukni jestli tam jsou i obyc soubory a vypis chybu
		if [ "$check" != "$slozky" ]; then
			soubory=`find "$check" -maxdepth 1 ! -type d`
			if [ "$soubory" ]; then
				retvalue=1
				echo "Prepinac -v. Ve slozce $check jsou soubory i slozky." >&2
			fi
		fi
		counter=`expr $counter + 1`
		check=`echo $b | cut -d ' ' -f$counter`
	done
			

	#############
	#jsou ve strome symbolicke odkazy?
	sym=`find . -type l | grep -E ".*$regex.*"`
	if [ "$sym" ]; then
		retvalue=1
		echo "Prepinac -v. Ve strome jsou symbolicke odkazy: $sym." >&2
	fi
	
	#############
	#jsou ve strome vicenasobne pevne odkazy?
	hard=`find . -type f -a ! -links 1 | grep -E ".*$regex.*"`
	if [ "$hard" ]; then
		retvalue=1
		echo "Prepinac -v. Ve strome jsou vicenasobne pevne odkazy: $hard." >&2
	fi

	#############
	#cmd-given, opravneni spoustet, kazde slozce, ktera neobsahuje podslozky
	a=`find . -type d | grep -E ".*$regex.*"`
	a="$a .END"
	counter=1
	check=`echo $a | cut -d ' ' -f$counter`
	
	lokace=`pwd`
	while [ "$check" != ".END" ]; do
		cd "$check"
		if [ $? -ne 0 ]; then
			retvalue2=2
			echo "Prepinac -v. Interni chyba skriptu. Operace cd $check selhala." >&2
		else
			pom=`find . -maxdepth 1 -type d`

			if [ "$pom" = "." ]; then
				pom2=`find . -maxdepth 1 | grep -E "cmd-given"`
				if [ -z "$pom2" ]; then
					retvalue=1	
					echo "Prepinac -v. V Adresari $check chybi soubor cmd-given." >&2
				fi
			fi
		fi
		counter=`expr $counter + 1`
		check=`echo $a | cut -d ' ' -f$counter`
		cd "$lokace"	
	done


	cmd_given=`find . ! -perm -0100 | grep -E ".*$regex.*cmd-given"`
	if [ "$cmd_given" ]; then
		retvalue=1
		echo "Prepinac -v. Uzivatel nema prava na spusteni souboru $cmd_given." >&2
	fi
	
	#############
	#jsou vsechny stdin-given pristupne pro cteni?
	given=`find . ! -perm -0400 | grep -E ".*$regex.*stdin-given"`
	if [ "$given" ]; then
		retvalue=1
		echo "Prepinac -v. Soubor(y) $given neni pristupny pro cteni." >&2
	fi


	#############
	#jsou vsechny {stdout,stderr,status}-{expected,captured,delta} pristupne pro zapis?
	mnoz=`find . ! -perm -0200 | grep -E ".*$regex.*st(dout|derr|atus)-(expected|captured|delta)"`
	if [ "$mnoz" ]; then
		retvalue=1
		echo "Prepinac -v. Soubor(y) $mnoz neni pristupny pro zapis ." >&2
	fi
	
	#############
	#obsahuji soubory status-{expected,captured} pouze cele cislo nasledovane koncem souboru?
	stat=`find . | grep -E ".*$regex.*status-(expected|captured)"`
	stat="$stat .END"
	counter=1
	check=`echo $stat | cut -d ' ' -f$counter`
	
	lines=`wc -l $check | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
	if [ $? -ne 0 ]; then
		retvalue=1
		echo "Prepinac -v. Operace wc selhala, soubor $check nelze prohlednout." >&2
	fi
	if [ $lines -eq 1 ]; then

		while [ "$check" != ".END" ]; do
			checkinside=`cat $check`
			if [ $? -ne 0 ]; then
				retvalue=1
				echo "Prepinac -v. Operace cat selhala, soubor $check nelze prohlednout." >&2
			fi
			#testuje zda v souboru neni pouze 0 nebo -0
			if ! [[ "$checkinside" =~ ^-?0$ ]]; then
				#pokud tam neni 0 ani -0, tak testuje obsah na cisla v desitkovem tvaru (tzn. 075 nevyhovi)
				if ! [[ "$checkinside" =~ ^-?[1-9][0-9]*$ ]]; then
					retvalue=1
					echo "Prepinac -v. Nevalidni obsah souboru $check." >&2
				fi
			fi
			counter=`expr $counter + 1`
			check=`echo $stat | cut -d ' ' -f$counter`
		done
	else
		retvalue=1
		echo "Prepinac -v. Prilis mnoho radku v souboru $check." >&2
	fi

	#############
	#jsou ve stromu pouze adresare a soubory, ktere tam maji byt?	
	test_tree=`find . ! -type d | grep -E ".*$regex.*" |grep -Ev "st(dout|derr|atus)-(expected|captured|delta)" | grep -Ev "cmd-given" | grep -Ev "stdin-given"`
	if [ "$test_tree" ]; then
		retvalue=1
		echo "Prepinac -v. Ve strome jsou neocekavane soubory: $test_tree." >&2
	fi

	

fi

#prepinac -t
if [ $t -eq 1 ]; then
	a=`find . -type d | grep -E ".*$regex.*"`
	a="$a .END"
	counter=1

	check=`echo $a | cut -d ' ' -f$counter`

	lokace=`pwd`

	while [ "$check" != ".END" ]; do
		cd "$check"
		if [ $? -ne 0 ]; then
			retvalue=2
			echo "Pepinac -t. Chyba pri operaci cd $check." >&2
		fi
		
		#zjisti, zda je v adresari soubor cmd-given
		pom_cmd=`find . -maxdepth 1 | grep -E "cmd-given"`
		if [ "$pom_cmd" ]; then

			#zjisti, zda je v adresari soubor stdin-given
			pom_stdin=`find . -maxdepth 1 | grep -E "stdin-given"`
			if [ "$pom_stdin" ]; then			
				$pom_cmd <$pom_stdin >"stdout-captured" 2>"stderr-captured"
				echo $? >"status-captured"
			else
				$pom_cmd <"/dev/null" >"stdout-captured" 2>"stderr-captured"
				echo $? >"status-captured"
			fi
			diff -up "status-captured" "status-expected" >"status-delta" 2>/dev/null
			d1=$?	
			diff -up "stderr-captured" "stderr-expected" >"stderr-delta" 2>/dev/null
			d2=$?
			diff -up "stdout-captured" "stdout-expected" >"stdout-delta" 2>/dev/null
			if [ $? -eq 2 -o $d1 -eq 2 -o $d2 -eq 2 ]; then
				echo "Prepinac -t. Pri operaci diff v adresari $check doslo k chybe" >&2
			fi
			
			#do promenny uloz pocet radku souboru
			delta1=`wc -l status-delta | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
			d1=$?
			delta2=`wc -l stderr-delta | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
			d2=$?
			delta3=`wc -l stdout-delta | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
			if [ $d1 -ne 0 -o $d2 -ne 0 -o $? -ne 0 ]; then
				echo "Prepinac -t. Chyba pri operaci wc nad X-delta." >&2
			fi

			check=`echo $check | cut -c3-`
			#ma li soubor 0 radku, je PRAZDY ocividne
			if [ $delta1 -eq 0 -a $delta2 -eq 0 -a $delta3 -eq 0 ]; then
				res="OK"
				echo -e "$check: \033[0;32mOK\033[0m" >&2
			else
				retvalue=1
				echo -e "$check: \033[0;31mFAILED\033[0m" >&2
			fi

		fi
		counter=`expr $counter + 1`
		check=`echo $a | cut -d ' ' -f$counter`
			
		#navrat do puvodniho adresare
		cd "$lokace"
	done

fi


#prepinac -r
if [ $r -eq 1 ]; then

	a=`find . -type d | grep -E ".*$regex.*"`
	a="$a .END"
	counter=1

	check=`echo $a | cut -d ' ' -f$counter`

	lokace=`pwd`

	while [ "$check" != ".END" ]; do
		cd "$check"
		if [ $? -ne 0 ]; then
			retvalue=2
			echo "Pepinac -r. Chyba pri operaci cd $check." >&2
		fi
		
		#zjisti, zda je v adresari soubor cmd-given
		pom_cmd=`find . -maxdepth 1 | grep -E "cmd-given"`
		if [ "$pom_cmd" ]; then

			diff -up "status-captured" "status-expected" >"status-delta" 2>/dev/null
			d1=$?	
			diff -up "stderr-captured" "stderr-expected" >"stderr-delta" 2>/dev/null
			d2=$?
			diff -up "stdout-captured" "stdout-expected" >"stdout-delta" 2>/dev/null
			if [ $? -eq 2 -o $d1 -eq 2 -o $d2 -eq 2 ]; then
				echo "Prepinac -r. Pri operaci diff v adresari $check doslo k chybe" >&2
			fi
			
			#do promenne uloz pocet radku souboru
			delta1=`wc -l status-delta | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
			d1=$?
			delta2=`wc -l stderr-delta | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
			d2=$?
			delta3=`wc -l stdout-delta | sed "s/^[ ]*\([0-9]*\).*/\1/g"`
			if [ $d1 -ne 0 -o $d2 -ne 0 -o $? -ne 0 ]; then
				echo "Prepinac -r. Chyba pri operaci wc nad X-delta." >&2
			fi

			check=`echo $check | cut -c3-`
			#ma li soubor 0 radku, je PRAZDY ocividne
			if [ $delta1 -eq 0 -a $delta2 -eq 0 -a $delta3 -eq 0 ]; then
				res="OK"
				echo -e "$check: \033[0;32mOK\033[0m"
			else
				retvalue=1
				echo -e "$check: \033[0;31mFAILED\033[0m"
			fi

		fi
		counter=`expr $counter + 1`
		check=`echo $a | cut -d ' ' -f$counter`
			
		#navrat do puvodniho adresare
		cd "$lokace"
	done

fi


#prepinac s - prejmenovavani souboru
if [ $s -eq 1 ]; then
	counter=1
	#do vektoru ulozi cesty k {souborum stdout,stderr,status}-captured
	vector=`find . | grep -E ".*$regex.*st(dout|derr|atus)-captured"`
	vector="$vector .END"
	pomA=`echo $vector | cut -d ' ' -f$counter`
	
	
	while [ "$pomA" != '.END' ]; do
		pomdir=`dirname "$pomA"`
		if [ $? -ne 0 ]; then
			retvalue=1
			echo "Prepinac -s. Vyskytla se chyba u prikazu dirname." >&2
		fi
		pombase=`basename "$pomA"`
		if [ $? -ne 0 ]; then
			retvalue=1
			echo "Prepinac -s. Vyskytla se chyba u prikazu basename." >&2
		fi
		#nahradi basename
		if [ "$pombase" = "stdout-captured" ]; then
			newname="$pomdir/stdout-expected"
		elif [ "$pombase" = "stderr-captured" ]; then
			newname="$pomdir/stderr-expected"
		elif [ "$pombase" = "status-captured" ]; then
			newname="$pomdir/status-expected"
		fi
		
		#prejmenuje soubor
		mv -f "$pomA" "$newname"
		if [ $? -ne 0 ]; then
			retvalue=1
			echo "Prepinac -s.Chyba mv pri prejmenovavani souboru $pomA." >&2
		fi

		counter=`expr $counter + 1`
		pomA=`echo $vector | cut -d ' ' -f$counter`		
	done
fi

#prepinac c - smaze dane soubory
if [ $c -eq 1 ]; then
	vectorB=`find . | grep -E ".*$regex.*st(dout|derr|atus)-(captured|delta)"`
	counter=1
	
	vectorB="$vectorB .END"
	smaz=`echo $vectorB | cut -d ' ' -f$counter`
	counter=`expr $counter + 1`
	while [ "$smaz" != '.END' ]; do
		rm -f "$smaz"
		if [ $? -ne 0 ]; then
			retvalue=1
			echo "Prepinac -c. Chyba prikazu rm pri mazani souboru $smaz." >&2
		fi

		smaz=`echo $vectorB | cut -d ' ' -f$counter`
		counter=`expr $counter + 1`
		#echo "$smaz $counter"
	done
fi

if [ $retvalue2 -eq 2 ]; then
	exit 2
fi
exit $retvalue;
	
