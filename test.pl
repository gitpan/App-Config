# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use strict;
use vars qw($loaded);

BEGIN { 
    $| = 1; 
    print "1..8\n"; 
}

END {
    ok(0) unless $loaded;
}

my $ok_count = 1;
sub ok {
    shift or print "not ";
    print "ok $ok_count\n";
    ++$ok_count;
}

use App::Config;
$loaded = 1;
ok(1);


my $ac = App::Config->new({ 
	GLOBAL => { 
	    CMDARG   => 1,
	    ARGCOUNT => 1,
	} 
    });

ok(defined $ac);

$ac->define('one', {
       	DEFAULT => 1,
	ALIAS   => "first",
    });

$ac->define('two', {
	DEFAULT => 2,
	ALIAS   => [ qw(second runnerup) ],
    });

$ac->define('three', {
	DEFAULT  => 3,
	CMDARG   => '-3',
    });

$ac->define('four', {
	DEFAULT  => 0,
	ALIAS    => 'village',
	ARGCOUNT => 0,
    });


my $ONE = 'I am the new number one';
my $TWO = 'I am not a number';
my $TRE = 'I am a three man';
my @args = ('-one', $ONE, '-second', $TWO, '-3', $TRE, '-village');

ok($ac->cmd_line(\@args));

ok($ac->one   eq $ONE);
ok($ac->two   eq $TWO);
ok($ac->three eq $TRE);
ok($ac->four);


print "Testing error handling: expect to see error messages...\n";
ok(! $ac->cmd_line(['-one', undef, '-nothing']));
print "Error handling tests complete.\n";


