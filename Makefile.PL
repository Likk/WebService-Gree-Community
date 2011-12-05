use inc::Module::Install;
name 'WebService-Gree-Community';
all_from 'lib/WebService/Gree/Community.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

test_requires 'Test::More';
auto_set_repository;
auto_include;
WriteAll;
