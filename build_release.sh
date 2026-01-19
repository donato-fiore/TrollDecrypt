rm -rf dist
mkdir dist

make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=
cp -p "`ls -dtr1 packages/* | tail -1`" ./dist/

make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
cp -p "`ls -dtr1 packages/* | tail -1`" ./dist/

cp -p TrollDecrypt.tipa ./dist/