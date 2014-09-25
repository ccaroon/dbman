package alter_table_dbman_test_table;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
use constant UP => <<'EOF';
alter table dbman_test_table add column code_name varchar(32) not null default '';
EOF
################################################################################
use constant DOWN => <<'EOF';
alter table dbman_test_table drop column code_name;
EOF
################################################################################
1;
