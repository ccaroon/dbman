package migration_with_compile_time_error;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
sub up {
    my ( $class, $dbh ) = @_;
################################################################################
sub down {
    my ( $class, $dbh ) = @_;
}
################################################################################
1;
