package bad_sql_statements;
################################################################################
use strict;

use lib "$ENV{DBMAN_HOME}/lib";
use base 'Migration::Base';
################################################################################
use constant UP => <<'EOF';
select * form table x;
EOF
################################################################################
use constant DOWN => <<'EOF';
inser int table x (1,2,3);
EOF
1;
