# Dila-sync

This script uses wget (required), git (optionnal) and pv (optionnal).

## Usage
```shell
./dila-sync.sh [-hgv]
```
- `h` print help
- `v` verbose
- `g` use git for versionning. **Be warned that if you use git for versionning
  it's gonna take forever (more than 12 hours on my current machine) to complete
  the first run.**

## Useful commands


### Delete empty directories

```shell
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
