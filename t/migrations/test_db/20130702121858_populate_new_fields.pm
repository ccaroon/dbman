package populate_new_fields;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
sub up {
    my ( $class, $dbh ) = @_;

    my $sth = $dbh->prepare("select id,name from dbman_test_table");
    $sth->execute();

    my $sql;
    while ( my $row = $sth->fetchrow_hashref() ) {
        my $code_name = $row->{name};
        $code_name =~ s/[^a-zA-Z0-9]/_/g;

        $sql
            .= "update dbman_test_table set code_name = '$code_name' where id=$row->{id};\n";
    }

    return ($sql);
}
################################################################################
sub down {
    my ( $class, $dbh ) = @_;

    $dbh->do("update dbman_test_table set code_name=''");

    return (undef);
}
################################################################################
1;
