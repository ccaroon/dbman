package populate_dbman_test_table;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
sub up {
    my ( $class, $dbh ) = @_;

    my $count = 0;
    foreach my $key qw(foo bar baz bop beep dup plop) {
        $dbh->do(
            "insert into dbman_test_table (name,value,is_core) values ('$key', $count, 1)"
        );
        $count++;
    }

    return (undef);
}
################################################################################
sub down {
    my ( $class, $dbh ) = @_;

    foreach my $key qw(foo bar baz bop beep dup plop) {
        $dbh->do("delete from dbman_test_table where name='$key'");
    }

    return (undef);
}
################################################################################
1;
