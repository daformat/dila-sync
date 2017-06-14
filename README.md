# Dila-sync

This script uses [wget](https://www.gnu.org/software/wget/) (required), [git](https://git-scm.com/) (optionnal) and pv (optionnal) to synchronize one or many of the following open data .xml stocks from France's [DILA (Direction de l'Information Légale et Adminsitrative)](http://www.dila.premier-ministre.gouv.fr/) legal datasets (données juridiques).


## Supported legal open datasets

Name       | Description and url
-----------|--------------------
LEGI       | Codes, lois et règlements consolidés <br> ftp://ftp2.journal-officiel.gouv.fr/LEGI/
JORF       | Textes publiés au Journal officiel de la République française <br> ftp://ftp2.journal-officiel.gouv.fr/JORF/
KALI       | Conventions collectives nationales <br> ftp://ftp2.journal-officiel.gouv.fr/KALI/
CASS       | Arrêts publiés de la Cour de cassation <br> ftp://ftp2.journal-officiel.gouv.fr/CASS/
INCA       | Arrêts inédits de la Cour de cassation <br> ftp://ftp2.journal-officiel.gouv.fr/INCA/
CAPP       | Décisions des cours d’appel et des juridictions judiciaires de premier degré <br> ftp://ftp2.journal-officiel.gouv.fr/CAPP/
CONSTIT    | Décisions du Conseil constitutionnel <br> ftp://ftp2.journal-officiel.gouv.fr/CONSTIT/
JADE       | Décisions des juridictions administratives <br> ftp://ftp2.journal-officiel.gouv.fr/JADE/
CNIL       | Délibérations de la CNIL <br> ftp://ftp2.journal-officiel.gouv.fr/CNIL/
SARD       | Référentiel thématique sur la majeure partie des textes législatifs et réglementaires en vigueur <br> ftp://ftp2.journal-officiel.gouv.fr/SARD/

JORFSIMPLE is **not supported yet** (Version simplifiée du Journal officiel - ftp://ftp2.journal-officiel.gouv.fr/JORFSIMPLE/)

For a more detailed explanation, view [Licences données juridiques (page in french)](http://rip.journal-officiel.gouv.fr/index.php/pages/juridiques) on DILA's Répertoire des Informations Publiques.


## Usage

```shell
./dila-sync.sh [-hgv] [-l rate_limit] stock_name [stock_name...]
```

### Options
- `-h` print help
- `-g` use git for versioning. **See below**
- `-v` verbose

- `-l` `rate_limit` limit wget download rate to `rate_limit`.

### Arguments
**`stock_name`**  
You have to provide at least one `stock_name` for `dila-sync` to synchronize it, see the list above for the supported stocks. `stock_name` can be either uppercase, lowercase, or a mix of it if you're feeling funky.


## Versioning with git

In order to use git to version some parts of the stock, you need to create a file called `.dila-sync-gitwatch` in the script folder **before running `./dila-sync.sh -g`**.

This file should contain **no more than a single path to version per line, relative to the script directory (so it must include ./stock)**

**Example**
```shell
# Create .dila-sync-gitwatch
touch .dila-sync-gitwatch
# Version the whole CNIL stock
echo "./stock/cnil" >>> .dila-sync-gitwatch
# Version only LEGITEXT000006074068 in the LEGI stock
# (code des pensions militaires...)
echo "./stock/legi/global/code_et_TNC_en_vigueur/code_en_vigueur/LEGI/TEXT/00/00/06/07/40/LEGITEXT000006074068" >>> .dila-sync-gitwatch
# Add as many directories you need to version with git
# ...
```


## Useful commands

### Delete empty directories
We're not automatically cleaning empty directories after each delta is applied, so every once in a whil it might be a good idea to run the following command in the `stock` directory
```shell
# Find and remove empty directories in current folder
find . -type d -empty -delete
```

### List every codes in stock

```shell
codes="./stock/legi/global/code_et_TNC_en_vigueur/code_en_vigueur"
ls "$codes"/*/*/*/*/*/*/*/* | grep ".stock" | sed 's/:$//g'
```

### Find any xml file that changed in the last 100 days

```shell
find . -type f -mtime -100 -name "*.xml" -printf "%TD %TR %p\n"
```

### Restrict to a specific code (or folder)
Simply change the starting point of find (here we are using a variable for the path we're interested in):

```shell
find_in="./legi/global/code_et_TNC_en_vigueur/code_en_vigueur/LEGI/TEXT/00/00/06/07/40/LEGITEXT000006074068"
find $find_in -type f -mtime -100 -name "*.xml" -printf "%TD %TR %p\n"
```

## Using git

### View the last commit with diff in a specific folder
```shell
look_in="./legi/global/code_et_TNC_en_vigueur/code_en_vigueur/LEGI/TEXT/00/00/06/07/40/LEGITEXT000006074068"
git log -p -1 -s -- $look_in
```


## Dev commands

If you need to quickly reset everything to a blank state, here are the steps:

```shell
# Remove .dila-sync folder
rm -rf ./.dila-sync;
# Remove the stock
rm -rf ./stock;
# Optionaly #
# Remove the archive files if you want to re-download everything
# rm -rf ./.tmp;
```
