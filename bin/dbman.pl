#!/usr/bin/env perl
use strict;

use Getopt::Long;

use lib "$ENV{DBMAN_HOME}/lib";
use DBMan;

use constant DEFAULT_ENV => 'devel';
use constant DEFAULT_CONFIG_FILE => "$ENV{DBMAN_HOME}/conf/dbman.pl.yml";

my $env;
my $config;
my $db;
my $help;
GetOptions(
    "env=s"    => \$env,
    "config=s" => \$config,
    "db=s"     => \$db,
    "help"     => \$help,
);

help() and exit(0) if $help;
die "Missing required parameter --db.\n" unless defined $db;

$env ||= DEFAULT_ENV;
$config ||= DEFAULT_CONFIG_FILE;
################################################################################
my $cmd = shift || '';

if ( $cmd and DBMan->can($cmd) ) {
    my $output;
    eval {
        my $dbman = DBMan->new(
            db          => $db,
            env         => $env,
            config_file => $config
        );
        $output = $dbman->$cmd(@ARGV);
    };
    if ($@) {
        print STDERR "'$cmd' command failed: $@\n";
    }
    else {
        print "'$cmd' successfully run on '$db' database in '$env' environment.\n$output\n";
    }
}
else {
    warn "Unknown command: '$cmd'.\n" if $cmd;
    help();
}
################################################################################
sub help {
    print <<EOF;
Usage: $0 <cmd> <--db DB_NAME> [--env ENV] [--config path/to/config.yml]

Options:
    
    * --env 
        By default all commands will use the 'devel' environment. 
        In order to specify a different environment, use the `--env` option.

    * --config
        By default uses the config file found in conf/dbman.pl.yml.
        You can use a different config file by specifying the `--config` option.
        See conf/example.yml for config explanation.

    * --db
        The name of a database from the `databases` section of the config file.
        *Required*

Environments:

    * devel
    * test
    * prod

Commands:

    * init_migrations: Initalizes a database for use with DBMan migrations.
                       Only needs to be run once on any given database.
        - Args: None
        - Example: $0 init_migrations --db main
    * create_migration: Create a new migration. New migration files will be 
                        written to a sub-directory of the `migration_dir` 
                        specifed in the config file. The sub-directory will be
                        the same as the specified `--db` parameter.
        - Args:
            - description - A string describing what your migration does.
        - Example: $0 create_migration --db main 'add age field to person table'
    * migrate: Runs the necessary migrations to get database schema to
               the specified version.
        - Args: 
            - version: Optional. Defaults to latest version.
        - Examples:
            1. $0 migrate --db main
            2. $0 migrate --db main 20111110142300
    * shell: Drops you into a mysql shell for the given environment.
        - Args: None
        - Examples:
            1. $0 shell --db main
            2. $0 shell --db main --env test
    * dump_schema: Writes the database schema out to a file.
        - Args: None
        - Example: $0 dump_schema --db main
EOF
}
################################################################################
