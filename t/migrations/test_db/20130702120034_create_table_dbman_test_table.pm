package create_table_dbman_test_table;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
use constant UP => <<'EOF';
create table dbman_test_table (
    id      bigint unsigned not null auto_increment,
    name    varchar(255) not null,
    value   varchar(255) not null,
    is_core tinyint unsigned not null default 0,

    primary key (id)
);
EOF
################################################################################
use constant DOWN => <<'EOF';
drop table dbman_test_table;
EOF
##############################################################################
1;
