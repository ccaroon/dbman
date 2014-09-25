package DBMan;
use strict;

use feature 'switch';
##############################################################################
use Date::Format;
use DBI;
use File::Path qw(make_path);
use File::Slurp;
use YAML::Syck;

use constant MIGRATE_NONE          => 'None';
use constant MIGRATE_UP            => 'Up';
use constant MIGRATE_DOWN          => 'Down';
use constant DEFAULT_MIGRATION_DIR => "$ENV{DBMAN_HOME}/migrations";
##############################################################################
sub new {
    my $class = shift;
    my %args = @_ or {};

    die "Missing required parameter 'db'." unless defined $args{db};

    $args{env} ||= 'devel';

    my $self = \%args;
    bless $self, $class;

    $self->_load_config();

    return ($self);
}
##############################################################################
sub _load_config {
    my $self = shift;

    die "Invalid config file: '$self->{config_file}'"
        unless -f $self->{config_file};

    $self->{config} = LoadFile( $self->{config_file} );

    # Migration Directory
    my $config = $self->config();
    $self->_set_migration_dir($config->{migration_dir});
}
################################################################################
sub init_migrations {
    my $self = shift;

    my $dbh = $self->dbh();

    my @tables = $dbh->tables();
    my $exists =
        ( grep /dbman_schema_migrations/, @tables )
        ? 1
        : 0;

    if ($exists) {
        die "`dbman_schema_migrations` table already exists on `"
            . $self->env() . "`.\n";
    }
    else {
        my $create_table_sql = <<'EOF';
CREATE TABLE `dbman_schema_migrations`
(
    `version`      bigint(20) unsigned NOT NULL DEFAULT '0',
    `applied_date` datetime            NOT NULL DEFAULT '0000-00-00 00:00:00',
    UNIQUE KEY `uk_version` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
EOF

        $dbh->do('DROP TABLE IF EXISTS `dbman_schema_migrations`;');
        $dbh->do($create_table_sql);
    }

    return;
}
################################################################################
sub create_migration {
    my $self = shift;
    my $name = shift or die "Create Migration Error: Please specify a name.";

    $name =~ s/[^A-Za-z0-9]/_/g;
    my $version = time2str( "%Y%m%d%H%M%S", time );

    my $template = <<EOT;
package $name;
################################################################################
use strict;

use lib "\$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
# Please use semi-colon-separated SQL statements
################################################################################
use constant UP => <<'EOF';
EOF
################################################################################
use constant DOWN => <<'EOF';
EOF
################################################################################
# up() and down() should return either 'undef' or valid, comman-separated SQL
################################################################################
#sub up
#{
#    my (\$class, \$dbh) = \@_;
#    my \$sql = undef;
#
#    return (\$sql);
#}
################################################################################
#sub down
#{
#    my (\$class, \$dbh) = \@_;
#    my \$sql = undef;
#
#    return (\$sql);
#}
################################################################################
1;
EOT

    make_path($self->config('migration_dir'));
    my $filename = $self->config('migration_dir') . "/${version}_$name.pm";
    write_file( $filename, $template );

    return ($filename);
}
################################################################################
sub migrate {
    my $self = shift;
    my $to_version = shift || 99999999999999;

    my $dbh = $self->dbh();

    my @migrations =
        grep {/^\d{14}_.*\.pm$/} read_dir( $self->config('migration_dir') );

    my $cols = $dbh->selectcol_arrayref(
        'select * from dbman_schema_migrations order by version');
    my @applied_migs = @$cols;

    my @migrations_to_apply;
    foreach my $file ( sort @migrations ) {
        $file =~ /^(\d{14})_(.*)\.pm/;
        my $version   = $1;
        my $mig_class = $2;

        my $applied = ( grep /$version/, @applied_migs ) ? 1 : 0;

        my $direction = MIGRATE_NONE;
        if ($applied) {
            if ( $version > $to_version ) {
                $direction = MIGRATE_DOWN;
            }
        }
        else {
            if ( $version <= $to_version ) {
                $direction = MIGRATE_UP;
            }
        }

        given ($direction) {
            when (MIGRATE_UP) {
                push @migrations_to_apply,
                    {
                    file      => $file,
                    version   => $version,
                    class     => $mig_class,
                    direction => $direction
                    };
            }
            when (MIGRATE_DOWN) {
                unshift @migrations_to_apply,
                    {
                    file      => $file,
                    version   => $version,
                    class     => $mig_class,
                    direction => $direction
                    };
            }
        }
    }

    # @migrations_to_apply will look similar to this [dn3,dn2,dn1,up1,up2,up3]
    # Downs are applied in reverse order FIRST, then Ups in sequence
    my $count = $self->_apply_migrations( \@migrations_to_apply );

    return ($count);
}
##############################################################################
sub _apply_migrations {
    my $self       = shift;
    my $migrations = shift;

    my $dbh   = $self->dbh();
    my $count = 0;

    # AutoCommit off == Start a transaction
    $dbh->{AutoCommit} = 0;

    my $current_mig;
    eval {
        foreach my $mig (@$migrations) {

            $current_mig = $mig;
            require $mig->{file};

            my $sql =
                  $mig->{direction} eq MIGRATE_UP
                ? $mig->{class}->up($dbh)
                : $mig->{class}->down($dbh);

            # Run any SQL returned by the migration
            if ($sql) {
                $sql =~ s/\n//g;
                my @statements = split /;/, $sql;
                map { $dbh->do($_) } @statements;
            }

            $mig->{direction} eq MIGRATE_UP
                ? $dbh->do(
                "insert into dbman_schema_migrations values ($mig->{version}, now())"
                )
                : $dbh->do(
                "delete from dbman_schema_migrations where version='$mig->{version}'"
                );

            $count++;
        }
    };
    if ($@) {
        $dbh->rollback();
        $dbh->{AutoCommit} = 1;
        die
            "Error migrating '$current_mig->{file}' -> $current_mig->{direction}: $@";
    }
    else {
        $dbh->commit();
        $dbh->{AutoCommit} = 1;
    }

    return ($count);
}
################################################################################
sub shell {
    my $self = shift;

    my $db = $self->config('databases')->{$self->{db}};
    exec("mysql -h$db->{host} -u$db->{user} $db->{db} -p$db->{pass}");
}
################################################################################
sub dump_schema {
    my $self        = shift;
    my $schema_file = "$self->{env}_schema.sql";

    # HEADER
    my $schema = <<EOF;
/*!40014 SET \@OLD_UNIQUE_CHECKS=\@\@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET \@OLD_FOREIGN_KEY_CHECKS=\@\@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;

-- -----------------------------------------------------------------------------

EOF

    # BODY == Create table statements
    my $dbh  = $self->dbh();
    my $stmt = $dbh->prepare("show tables");
    $stmt->execute();
    while ( my $row = $stmt->fetchrow_arrayref() ) {
        my $cs = $dbh->prepare("show create table `$row->[0]`");
        $cs->execute();
        my $info = $cs->fetchrow_arrayref();
        my $sql  = $info->[1];
        $cs->finish();

        $sql =~ s/\) ENGINE=(\w*) .*/) ENGINE=$1/m;
        $sql .= ';';

        $schema .= <<EOF;
-- $row->[0]
$sql

EOF
    }
    $stmt->finish();

    # FOOTER
    $schema .= <<EOF;
-- -----------------------------------------------------------------------------

/*!40014 SET FOREIGN_KEY_CHECKS=\@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=\@OLD_UNIQUE_CHECKS */;

EOF

    write_file( $schema_file, $schema );

    return ($schema_file);
}
##############################################################################
sub db {
    my $self = shift;
    return ($self->{db});
}
##############################################################################
sub env {
    my $self = shift;
    return ( $self->{env} );
}
##############################################################################
# Getter: All getting is relative to the `env` setting.
#   $dbman->config();           # Gets entire config
#   $dbman->config('databases'); # Gets a section of the config
# Setter:
#   Set a section of the config to a particular value
#   $dbman->config('migration_dir','/home/me/migrations');
##############################################################################
sub config {
    my $self    = shift;
    my $section = shift;
    my $value   = shift;

    my $config = $self->{config}->{ $self->{env} };
    if ( defined $section and defined $value ) {
        if ($section eq 'migration_dir') {
            $self->_set_migration_dir($value);
        }
        else {
            $config->{$section} = $value;            
        }
    }
    my $sub_cfg = ( defined $section ) ? $config->{$section} : $config;

    return ($sub_cfg);
}
##############################################################################
sub dbh {
    my $self = shift;

    my $db = $self->config('databases')->{$self->{db}};

    my $dbh = $self->{dbh};
    unless ($dbh) {
        $dbh = DBI->connect( "dbi:mysql:host=$db->{host};database=$db->{db}",
            $db->{user}, $db->{pass}, { RaiseError => 1, PrintError => 0 } );
        $self->{dbh} = $dbh;
    }

    return ($dbh);
}
##############################################################################
sub _set_migration_dir {
    my $self     = shift;
    my $mig_dir  = shift;

    if ($mig_dir) {

        # Prepend DBMAN_HOME unless `migration_dir` is an absolute path
        unless ( $mig_dir =~ m|^/| ) {
            $mig_dir = "$ENV{DBMAN_HOME}/$mig_dir";
        }
    }
    else {
        $mig_dir = DEFAULT_MIGRATION_DIR;
    }

    # Add sub-dir for database. We don't want the migrations for different 
    # databases in the same directory.
    my $config = $self->config();
    $config->{migration_dir} = "$mig_dir/$self->{db}";

    push @INC, $self->config('migration_dir');
}
##############################################################################
1;
