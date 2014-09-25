package DBManTest;
use base 'Test::Class';

use File::Slurp;
use File::Temp;
use Sub::Override;
use Test::Exception;
use Test::More;
use YAML::Syck;

use constant DEFAULT_DB     => 'test_db';
use constant DEFAULT_CONFIG => "$ENV{DBMAN_HOME}/conf/dbman.pl.yml";
use constant DEFAULT_ARGS   => ( 
    env         => 'test', 
    db          => DEFAULT_DB,
    config_file => DEFAULT_CONFIG
);
use constant TESTED_CLASS   => 'DBMan';
##############################################################################
sub before_all : Test(startup => 1) {
    my $self = shift;

    use_ok TESTED_CLASS;
}
##############################################################################
sub test_new : Test(7) {
    my $self = shift;

    throws_ok { TESTED_CLASS->new() } qr/Missing required parameter 'db'/,
        "should throw an error if missing the 'db' param";

    throws_ok { TESTED_CLASS->new(db => "foo") } qr/Invalid config file/,
        "should throw an error if not given a config file";

    throws_ok { TESTED_CLASS->new( db => 'foo', config_file => '/foo/bar/d.yml' ) }
    qr/Invalid config file/,
        "should throw an error if given config_file does not exist";

    throws_ok {
        TESTED_CLASS->new(
            db => 'foo',
            config_file => "$ENV{DBMAN_HOME}/t/conf/bad_config.yml" );
    }
    qr/Can't use string/, 
    "should throw an error if given config_file cannot be parsed";

    is TESTED_CLASS->new( db => 'foo', config_file => DEFAULT_CONFIG )->env(),
        'devel',
        "'env' should default to 'devel'";

    is TESTED_CLASS->new(DEFAULT_ARGS)->env(),
        'test',
        "should be able to set 'env'";

    is TESTED_CLASS->new(DEFAULT_ARGS)->db(),
        DEFAULT_DB,
        "should be able to set 'db'";
}
##############################################################################
sub test_config : Tests(10) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);

    # Can get entire config
    my $config = $dbman->config();
    is ref $config, 'HASH', "should be a HASHRef";
    ok exists $config->{databases}, "databases setting should exist.";

    # Can get section of config
    my $dbs = $dbman->config('databases');
    my $db = $dbs->{DEFAULT_DB()};

    is ref $db, 'HASH', "should be a HASHRef";
    ok exists $db->{host}, "'host' key should exist";
    ok exists $db->{user}, "'user' key should exist";
    ok exists $db->{pass}, "'pass' key should exist";
    ok exists $db->{db},   "'db' key should exist";

    # Set 'migration_dir' via config()
    my $mig_dir = $dbman->config('migration_dir');
    $dbman->config( 'migration_dir', '/foo/bar/baz' );
    my $mig_dir2 = $dbman->config('migration_dir');
    isnt $mig_dir, $mig_dir2, "migration_dir should no longer match old value";
    is $mig_dir2, "/foo/bar/baz/".DEFAULT_DB, "migration_dir should match new value";

    # Set a section of the config that is NOT migration_dir
    $dbman->config('foo_bar', 'Hello, World.');
    is $dbman->config('foo_bar'), "Hello, World.", 
        "should be able to set config sections"
}
##############################################################################
sub test_config_file : Test(5) {
    my $self = shift;

    # migration_dir -- relative path
    my $tmp_cfg =
        File::Temp->new( SUFFIX => '.yml', DIR => "/tmp" );
    print $tmp_cfg <<EOF;
test:
    migration_dir: 't/migrations'
EOF
    $tmp_cfg->flush();

    my $dbman =
        TESTED_CLASS->new( DEFAULT_ARGS, config_file => $tmp_cfg->filename );
    my $raw_cfg = LoadFile( $tmp_cfg->filename );
    my $config  = $dbman->config();
    unlike $raw_cfg->{test}->{migration_dir}, qr|^/|,
        "migration_dir should be a relative path, i.e. not start with a '/'";
    isnt $raw_cfg->{test}->{migration_dir}, $config->{migration_dir},
        "migration_dir in raw config should not match migration_dir in cooked config";
    is "$ENV{DBMAN_HOME}/$raw_cfg->{test}->{migration_dir}/".DEFAULT_DB,
        $config->{migration_dir},
        "cooked migration_dir should be relative to DBMAN_HOME and have 'db' appended";

    ## migration_dir -- absolute path
    $tmp_cfg =
        File::Temp->new( SUFFIX => '.yml', DIR => "/tmp" );
    print $tmp_cfg <<EOF;
test:
    migration_dir: '/home/some/path/to/the/migrations'
EOF
    $tmp_cfg->flush();
    $dbman =
        TESTED_CLASS->new( DEFAULT_ARGS, config_file => $tmp_cfg->filename );
    $raw_cfg = LoadFile( $tmp_cfg->filename );
    $config  = $dbman->config();
    like $raw_cfg->{test}->{migration_dir}, qr|^/|,
        "migration_dir should be an absolute path";
    is "$raw_cfg->{test}->{migration_dir}/".DEFAULT_DB, $config->{migration_dir},
        "migration_dir in raw config should match migration_dir in cooked config";
}
##############################################################################
sub test_init_migrations : Test(5) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    ok $dbman, "create new instance";

    # delete migration table if exists
    my $dbh = $dbman->dbh();
    ok $dbh->do('DROP TABLE IF EXISTS `dbman_schema_migrations`;'), "drop table";

    # run init_migrations
    $dbman->init_migrations();

    # check that table created
    my @tables = $dbh->tables();
    my $exists = grep /dbman_schema_migrations/, @tables;
    ok $exists, "migrations table should exist";

    # Run again and expect error
    throws_ok { $dbman->init_migrations() }
    qr/`dbman_schema_migrations` table already exists on `test`/,
        "should throw an error if the migrations table already exists";

    # Override `execute` to test unexpected error
    my $override = Sub::Override->new(
        "DBI::st::execute",
        sub {
            die "Unexpected database error.";
        }
    );

    throws_ok { $dbman->init_migrations() }
    qr/Unexpected database error/,
        "should throw an error if an unexptected error occurs.";
    $override->restore();
}
##############################################################################
sub test_create_migration : Test(5) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    ok $dbman;

    throws_ok { $dbman->create_migration() }
    qr/Create Migration Error: Please specify a name/,
        "should throw an error if not given a 'name' param";

    my $name = "unit test to test creating a migration";
    $dbman->create_migration($name);

    my $mig_dir  = $dbman->config('migration_dir');
    my @files    = read_dir($mig_dir);
    my $mig_name = $name;
    $mig_name =~ s/\s/_/g;
    my @found_files = grep /$mig_name/, @files;

    is scalar(@found_files), 1, "should have created a migration file";
    my $mig_file = "$mig_dir/$found_files[0]";
    ok -s $mig_file > 0, "migration file should not be empty";

    ok( ( unlink $mig_file ), "reset" );
}
##############################################################################
sub test_migrate_errors : Test(4) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    ok $dbman;

    $dbman->config( 'migration_dir',
        "$ENV{DBMAN_HOME}/t/migrations/error_scenario1" );
    push @INC, $dbman->config('migration_dir');
    throws_ok { $dbman->migrate() }
    qr/Error migrating '20130702112548_migration_with_compile_time_error.pm' -> Up: Missing right curly/,
        "Syntax error should cause migration to fail and rollback";

    $dbman->config( 'migration_dir',
        "$ENV{DBMAN_HOME}/t/migrations/error_scenario2" );
    push @INC, $dbman->config('migration_dir');
    throws_ok { $dbman->migrate() }
    qr/Error migrating '20130702113758_migration_with_runtime_error.pm' -> Up: Something \*really\* bad happened./,
        "Runtime error should cause migration to fail and rollback";

    $dbman->config( 'migration_dir',
        "$ENV{DBMAN_HOME}/t/migrations/error_scenario3" );
    push @INC, $dbman->config('migration_dir');
    throws_ok { $dbman->migrate() }
    qr/Error migrating '20130702114753_bad_sql_statements.pm' -> Up: DBD::mysql::db do failed: You have an error in your SQL syntax/,
        "Bad SQL should cause migration to fail and rollback";
}
##############################################################################
sub test_migrate : Test(17) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    my $dbh   = $dbman->dbh();

    # Migrate to latest version
    my $count = $dbman->migrate();
    is $count, 4, "should have run 4 migrations";
    my @tables = $dbh->tables();
    ok( ( grep /dbman_test_table/, @tables ),
        "should have created dbman_test_table"
    );
    my $data = $dbh->selectcol_arrayref(
        "select count(*) as count from dbman_test_table");
    ok $data->[0] > 0, "dbman_test_table should be populated";
    $data = $dbh->selectcol_arrayref("select code_name from dbman_test_table");
    ok @$data == 7, "should have migrated to latest version";

    # Reset
    $count = $dbman->migrate(1);
    is $count, 4, "resetting should have rolled back 4 migrations";

    # Migrate to specific version
    $count = $dbman->migrate(20130702120207);
    is $count, 2, "should have run 2 migrations";
    @tables = $dbh->tables();
    ok( ( grep /dbman_test_table/, @tables ),
        "should have created dbman_test_table"
    );
    $data = $dbh->selectcol_arrayref(
        "select count(*) as count from dbman_test_table");
    ok $data->[0] > 0, "dbman_test_table should be populated";
    throws_ok {
        $dbh->selectcol_arrayref("select code_name from dbman_test_table");
    }
    qr/Unknown column 'code_name'/,
        "should only have run the first 2 migrations";

    # Reset
    $count = $dbman->migrate(1);
    is $count, 2, "resetting should have rolled back 2 migrations";

    # Migrate to latest version
    $count = $dbman->migrate();
    is $count, 4, "should have run 4 migrations";
    @tables = $dbh->tables();
    ok( ( grep /dbman_test_table/, @tables ),
        "should have created dbman_test_table"
    );
    $data = $dbh->selectcol_arrayref(
        "select count(*) as count from dbman_test_table");
    ok $data->[0] > 0, "dbman_test_table should be populated";
    $data = $dbh->selectcol_arrayref("select code_name from dbman_test_table");
    ok @$data == 7, "should have migrated to latest version";

    # Rollback to specific version
    $count = $dbman->migrate(20130702120207);
    is $count, 2, "should have run 2 migrations";
    throws_ok {
        $dbh->selectcol_arrayref("select code_name from dbman_test_table");
    }
    qr/Unknown column 'code_name'/,
        "should have rolled back the last 2 migrations";

    # Reset
    $count = $dbman->migrate(1);
    is $count, 2, "resetting should have rolled back 2 migrations";
}
##############################################################################
sub test_migrate_error_causes_rollback : Test(9) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    ok $dbman;

    my $dbh = $dbman->dbh();

    # Set up
    $dbman->config( 'migration_dir',
        "$ENV{DBMAN_HOME}/t/migrations/error_scenario4" );
    push @INC, $dbman->config('migration_dir');

    my @tables = $dbh->tables();
    my $exists = grep /dbman_test_table/, @tables;
    ok !$exists, "dbman_test_table should NOT exist";

    # Migrate to specific version to get table created
    $dbman->migrate(20130702120034);
    @tables = $dbh->tables();
    $exists = grep /dbman_test_table/, @tables;
    ok $exists, "dbman_test_table should exist";
    my $data = $dbh->selectcol_arrayref(
        "select count(*) as count from dbman_test_table");
    ok $data->[0] == 0, "dbman_test_table should be empty";

    ## Migrate again to latest and cause failure
    throws_ok { $dbman->migrate() }
    qr/Error migrating '20130702120233_cause_an_error.pm' -> Up:/,
        "migration should cause an error and be rolled back";

    @tables = $dbh->tables();
    $exists = grep /dbman_test_table/, @tables;
    ok $exists, "dbman_test_table should STILL exist";

    $data = $dbh->selectcol_arrayref(
        "select count(*) as count from dbman_test_table");
    ok $data->[0] == 0, "dbman_test_table should STILL be empty";

    $data = $dbh->selectcol_arrayref(
        "select count(*) as count from dbman_schema_migrations");
    ok $data->[0] == 1,
        "dbman_schema_migrations table should only contain 1 entry";

    # Reset
    $count = $dbman->migrate(1);
    is $count, 1, "resetting should have rolled back 1 migration";
}
##############################################################################
sub test_dump_schema : Test(6) {
    my $self = shift;

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    ok $dbman;

    is $dbman->env(), 'test', "should be using the test environment";

    my $schema_file = "test_schema.sql";
    is -f $schema_file, undef, "schema file should not exists yet";

    $dbman->dump_schema();

    is -f $schema_file, 1, "schema file should exists now";
    ok -s $schema_file > 0, "schema file should not be empty";

    ok unlink $schema_file;
}
##############################################################################
sub test_shell : Test(1) {
    my $self = shift;

    # Overriding built-in function 'exec'
    # Couldn't find a better way
    # Sub::Override doesn't work for built-ins
    # NOTE: This GLOBALLY overrides 'exec' for the life of this perl process
    my $cmd;

    BEGIN {
        *CORE::GLOBAL::exec = sub {
            $cmd = shift;
        };
    }

    my $dbman = TESTED_CLASS->new(DEFAULT_ARGS);
    $dbman->shell();

    my $db = $dbman->config('databases')->{DEFAULT_DB()};
    is $cmd, "mysql -h$db->{host} -u$db->{user} $db->{db} -p$db->{pass}",
        "should 'exec' the mysql client command";
}
##############################################################################
1;
