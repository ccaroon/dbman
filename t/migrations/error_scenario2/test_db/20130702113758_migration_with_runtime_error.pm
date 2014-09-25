package migration_with_runtime_error;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
sub up {
    my ( $class, $dbh ) = @_;

    die "Something *really* bad happened.";
}
################################################################################
sub down {
    my ( $class, $dbh ) = @_;
}
################################################################################
1;
