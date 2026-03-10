#!/bin/bash
POSTGRES_PASSWORD="mysecret"
JWT_SECRET="jwtsecret"
JWT_EXPIRY="3600"
echo '\set pgpass `echo "$POSTGRES_PASSWORD"`' > roles.sql
echo '\set jwt_secret `echo "$JWT_SECRET"`' > jwt.sql
echo '\set jwt_exp `echo "$JWT_EXP"`' >> jwt.sql

sed -i "s|\\\\set pgpass \`echo \"\$POSTGRES_PASSWORD\"\`|\\\\set pgpass '${POSTGRES_PASSWORD}'|g" roles.sql
sed -i "s|\\\\set jwt_secret \`echo \"\$JWT_SECRET\"\`|\\\\set jwt_secret '${JWT_SECRET}'|g" jwt.sql
sed -i "s|\\\\set jwt_exp \`echo \"\$JWT_EXP\"\`|\\\\set jwt_exp '${JWT_EXPIRY}'|g" jwt.sql

cat roles.sql
cat jwt.sql
