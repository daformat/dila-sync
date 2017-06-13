# Dila-sync

This script uses wget (required), git (optionnal) and pv (optionnal) to synchronize the French DILA open data .xml stocks described below.

## Usage
```shell
./dila-sync.sh [-hgv] stock_name [stock_name...]
```
- `h` print help
- `v` verbose
- `g` use git for versionning. **See below**

You have to provide at least one `stock_name` for `dila-sync` to synchronize it, here is the list of the stocks supported:

- [legi](ftp://ftp2.journal-officiel.gouv.fr:21/LEGI/)
- [capp](ftp://ftp2.journal-officiel.gouv.fr:21/CAPP/)
- [cass](ftp://ftp2.journal-officiel.gouv.fr:21/CASS/)
- [cnil](ftp://ftp2.journal-officiel.gouv.fr:21/CNIL/)
- [constit](ftp://ftp2.journal-officiel.gouv.fr:21/CONSTIT/)
- [inca](ftp://ftp2.journal-officiel.gouv.fr:21/INCA/)
- [jade](ftp://ftp2.journal-officiel.gouv.fr:21/JADE/)
- [kali](ftp://ftp2.journal-officiel.gouv.fr:21/KALI/)
- [sarde](ftp://ftp2.journal-officiel.gouv.fr:21/SARDE/)

## Using git

In order to use git to version some parts of the stock, you need to create a file called `.dila-sync-gitwatch` in the script folder **before running `./dila-sync.sh -g`**.

This file should contain **no more than a single path to version per line, relative to the script directory (so it must include ./stock)**

** Example **
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
