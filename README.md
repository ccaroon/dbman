DBMan
-----

Setup
=====
1. Set the DBMAN_HOME environment variable: `export DBMAN_HOME=/path/to/your/code/core/util/dbman`
2. Add the DBMan `bin` directory to your path: `export PATH=$PATH:$DBMAN_HOME/bin`
3. Copy conf/example.yml to conf/dbman.pl.yml. Edit and set the necessary database settings.
3. If you changed your `.bashrc`, source it.
4. Change directory to the $DBMAN_HOME directory and run `prove -v`. If all tests
   pass, then your set. These test will by default use the 'test' environment, so
   make sure it points to an appropriate database.
