#!perl -Tw

use strict;
use warnings;

use Test::More qw(no_plan);

use_ok('Data::Beacon');

my $r;
my $b = new Data::Beacon();
isa_ok($b,'Data::Beacon');

is( $b->errorcount, 0 );

# meta fields
my %m = $b->meta();
is_deeply( \%m, { 'FORMAT' => 'BEACON' }, 'meta()' );

is_deeply( $b->meta('fOrMaT'), 'BEACON' );
is_deeply( $b->meta('foo'), undef );
is_deeply( $b->meta( {} ), undef );

# not allowed or bad arguments
my @badmeta = (
 [ 'a','b','c' ],
 [ 'format' => '' ],
 [ ' ' => 'x' ],
 [ '~' => 'x' ],
 [ 'prefix' => 'htt' ],    # invalid PREFIX
 [ 'Feed' => 'http://#' ], # invalid FEED
 [ 'target' => 'x' ],
 [ 'target' => 'u:ri' ],
 [ 'target' => 'http://example.com' ],
);
foreach my $bad (@badmeta) {
    eval { $b->meta( @$bad ); }; ok( $@ );
    if (@$bad == 2 && $bad->[0] ne ' ') {
        my $line = '#' . join(': ',@$bad) . "\n";
        my $c = Data::Beacon->new( \$line );
        is( $c->errorcount, 1, 'bad meta field' );
    }
}
is( $b->errorcount, 0, 'croaking errors are not counted' );

$b->meta( 'prefix' => 'http://foo.bar' );
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'PREFIX' => 'http://foo.bar' } );
$b->meta( 'prefix' => 'u:' ); # URI prefix
$b->meta( 'prefix' => '' );

eval { $b->meta( 'revisit' => 'Sun 3rd Nov, 1943' ); }; 
ok( $@ , 'detect invalid REVISIT');
$b->meta( 'REvisit' => '2010-02-31T12:00:01' );
is_deeply( { $b->meta() }, 
  { 'FORMAT' => 'BEACON', 
    'REVISIT' => '2010-03-03T12:00:01' } );
$b->meta( 'REVISIT' => '' );

is( $b->meta( 'EXAMPLES' ), undef );
$b->meta( 'EXAMPLES', 'foo | bar||doz ' );
is( $b->meta('EXAMPLES'), 'foo|bar|doz', 'EXAMPLES' );
$b->meta( 'EXAMPLES', '|' );
is( $b->meta('EXAMPLES'), undef );
$b->meta( 'EXAMPLES', '' );

$b->meta('foo' => 'bar ', ' X ' => " Y\nZ");
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'FOO' => 'bar', 'X' => 'YZ' } );
$b->meta('foo',''); # unset
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'X' => 'YZ' } );

eval { $b->meta( 'format' => 'foo' ); }; ok( $@, 'detect invalid FORMAT' );
$b->meta( 'format' => 'FOO-BEACON' );
is( $b->meta('format'), 'FOO-BEACON' );

is( $b->meta('COUNT'), undef, 'meta("COUNT")' );
is( $b->count, 0, 'count()' );
$b->meta('count' => 7);
is( $b->count, 7, 'count()' );
is( $b->line, 0, 'line()' );

$b = new Data::Beacon();
$b->meta( 'feed' => 'http://example.com', 'target' => 'http://example.com/{ID}' );
$b->meta( 'target' => 'http://example.com/{LABEL}' );
is( $b->meta('target'), 'http://example.com/{LABEL}' );

is( Data::Beacon::parsebeaconlink( undef ), undef );

# line parsing (invalid URI not checked)
my %t = (
  "qid" => ["qid","","",""],
  "qid|\t" => ["qid","","",""],
  "qid|" => ["qid","","",""],
  "qid|lab" => ["qid","lab","",""],
  "qid|  lab |dsc" => ["qid","lab","dsc",""],
  "qid| | dsc" => ["qid","","dsc",""],
  " qid||dsc" => ["qid","","dsc",""],
  "qid |u:ri" => ["qid","","","u:ri"],
  "qid |lab  |dsc|u:ri" => ["qid","lab","dsc","u:ri"],
  "qid|lab|u:ri" => ["qid","lab","","u:ri"],
  " \t" => [],
  "" => [],
  "qid|lab|dsc|u:ri|foo" 
      => "found too many parts (>4), divided by '|' characters",
  "|qid|u:ri" => [],
  "qid|lab|dsc|abc" => "URI part has not valid URI form",
);
while (my ($line, $link) = each(%t)) {
    $r = Data::Beacon::parsebeaconlink( $line );
    is_deeply( $r, $link );
}

%t = (
  "qid |u:ri" => ['qid','u:ri','',''] # TODO: add expansion here?
);
while (my ($line, $link) = each(%t)) {
    $r = Data::Beacon::parsebeaconlink( $line, 'http://example.org/{ID}' );
    is_deeply( $r, $link, 'parse link with #TARGET' );
}


# file parsing
$b = new Data::Beacon( "t/beacon1.txt" );
is_deeply( { $b->meta() }, {
  'FORMAT' => 'BEACON',
  'TARGET' => 'http://example.com/{ID}',
  'FOO' => 'bar',
  'PREFIX' => 'x:'
}, "parsing meta fields" );

is( $b->line, 6, 'line()' );
$b->parse();
is( $b->lasterror, "found too many parts (>4), divided by '|' characters" );

is( $b->errorcount, 1 );

eval { $b = new Data::Beacon( error => 'xxx' ); }; ok( $@, 'error handler' );
is( $b->errorcount, 1 );

$b->parse("xxx"); #; ok( $@, 'error parsing' );
is( $b->errorcount, 1 );

my $e = $b->lasterror;
is( $e, 'Failed to open xxx', 'lasterror, scalar context' );

my @es = $b->lasterror;
is_deeply( \@es, [ 'Failed to open xxx', 0, '' ], 'lasterror, list context' );

$b->parse( { } );
is( $b->errorcount, 1, 'cannot parse a hashref' );

# string parsing
$b->parse( \"x:from|x:to\n\n|comment" );
is( $b->count, 1, 'parse from string' );
is( $b->line, 3, '' );

my @l;
$b->parse( \"\xEF\xBB\xBFx:from|x:to", 'link' => sub { @l = @_; } );
is( $b->line, 1 );
is( $b->errorcount, 0 );
is_deeply( \@l, [ 'x:from', '', '', 'x:to', 'x:from', 'x:to' ], 'BOM' );

my @tmplines = ( '#FOO: bar', '#DOZ', '#BAZ: doz' );
$b->parse( from => sub { return shift @tmplines; } );
is( $b->line, 3, 'parse from code ref' );
is( $b->count, 0, '' );
is( $b->metafields, "#FORMAT: BEACON\n#BAZ: doz\n#FOO: bar\n#COUNT: 0\n" );

$b->parse( from => sub { die 'hard'; } );
is( $b->errorcount, 1 );
ok( $b->lasterror =~ /^hard/, 'dead input will not kill us' );

$b = new Data::Beacon( \"#COUNT: 2\nf:rom|t:o" );
is( $b->count, 2 );
ok( !$b->parse() );
is( $b->lasterror, "expected 2 links, but got 1", "check expected link count" );

# expected examples
$b = new Data::Beacon( \"#EXAMPLES: a:b|c:d\na:b|to:1\nc:d|to:2" );
ok( $b->parse() );

$b = new Data::Beacon( \"#EXAMPLES: a:b|c\na:b|to:1" );
$b->parse();
is_deeply( [ $b->lasterror ], [ 'examples not found: c',2,''], 'examples' );

$b = new Data::Beacon( \"#EXAMPLES: a\n#PREFIX x:\na|to:1" );
ok( $b->parse() );

$b = new Data::Beacon( \"#EXAMPLES: x:a\n#PREFIX x:\na|to:1" );
ok( $b->parse() );


# ensure that IDs are URIs
$b = new Data::Beacon( \"xxx |foo" );
$b->parse();
is_deeply( [ $b->lasterror ], [ 'id must be URI: xxx',1,'xxx |foo' ], 
            'skipped non-URI id' );

# pull parsing
$b = new Data::Beacon( \"\nid:1|t:1\n|comment\n" );
is_deeply( $b->nextlink, ["id:1","","","t:1",'id:1','t:1'] );
is_deeply( $b->nextlink, undef );

$b = new Data::Beacon( \"id:1|t:1\na b|\nid:2|t:2" );
is_deeply( $b->nextlink, ["id:1","","","t:1",'id:1','t:1'] );
is_deeply( $b->nextlink, ["id:2","","","t:2",'id:2','t:2'] );
is( $b->nextlink, undef );
is( $b->errorcount, 1 );
is_deeply( [ $b->lasterror ], [ 'id must be URI: a b',2,'a b|' ] );


use Data::Validate::URI qw(is_uri);

# check method 'getbeaconlink'
my @p = ( 
    ["","","",""],
    ["a","b","c","z"],
    ["a","b","","z"],
    ["a","","","z"],
    ["","","","http://example.com"]
);
while (@p) {
    my $in = shift @p;
    is( Data::Beacon::getbeaconlink( @{$in} ), '', 'getbeaconlink = ""');
}

@p = (
    ["a","b","c",""], "a|b|c",
    ["a","b","",""], "a|b",
    ["a","","",""], "a",
);
while (@p) {
    my $in = shift @p;
    my $out = shift @p;
    my $line = Data::Beacon::getbeaconlink( @{$in} );
    is( $line, $out, 'getbeaconlink');

    my $line = "#PREFIX: http://example.org/\n$line";
    $b = new Data::Beacon( \$line );
    ok( !$b->parse ); # TARGET is not an URI

    $line = "#TARGET: foo:{ID}\n$line";
    $b = new Data::Beacon( \$line );
    my $l = $b->nextlink();

    push @$in, "http://example.org/".$in->[0];
    push @$in, "foo:".$in->[0];

    is_deeply( $in, $l, 'getbeaconlink + PREFIX + TARGET' );
}

@p = ( # with 'to' field
    ["a","b","","foo:x"], "a|b|foo:x",
    ["a","","","foo:x"], "a|foo:x",
    ["a","b","c","foo:x"], "a|b|c|foo:x",
    ["x","a||","","http://example.com|"], "x|a|http://example.com",
    ["x","","|d","foo:bar"], "x||d|foo:bar",
    ["x","|","","http://example.com"], "x|http://example.com",
);
while (@p) {
    my $in = shift @p;
    my $out = shift @p;
    my $line = Data::Beacon::getbeaconlink( @{$in} );
    is( $line, $out, 'getbeaconlink');

    @$in = map { s/\|//g; $_; } @$in;
    my $line = "#PREFIX: http://example.org/\n$line";
    $b = new Data::Beacon( \$line );

    my $l = $b->nextlink();
    pop @$l; # fullid
    pop @$l; # fulluri
    
    is_deeply($l, $in);
}

# ignore additional params
is('x', Data::Beacon::getbeaconlink('x','','','','foo','bar'));

# link expansion

$b = new Data::Beacon( \"#TARGET: http://foo.org/{LABEL}\nf:rom|x" );
is_deeply( $b->nextlink, ['f:rom','x','','','f:rom','http://foo.org/x'] );

$b = new Data::Beacon( \"#TARGET: http://foo.org/{ID}\nx:y" );
is_deeply( $b->nextlink, ['x:y','','','','x:y','http://foo.org/x:y'] );

$b = new Data::Beacon( \"#PREFIX: u:\n#TARGET: z:{ID}\n\$1" );
is_deeply( $b->nextlink, ['$1','','','','u:$1','z:$1'] );

use Data::Dumper;
print Dumper( $b->nextlink() );

$b = new Data::Beacon( \"a:b|c:d" );
is_deeply( $b->nextlink, ['a:b','','','c:d','a:b','c:d'] );

$b = new Data::Beacon( \"#TARGET: f:{ID}\na:b|c:d" );
is_deeply( $b->nextlink, ['a:b','c:d','','','a:b','f:a:b'],
    'TARGET changes parsing' );

$b = new Data::Beacon( \"#TARGET: f:{LABEL}\na:b|c:d" );
is_deeply( $b->nextlink, ['a:b','c:d','','','a:b','f:c:d'],
    'TARGET changes parsing' );

# croaking link handler
$b = new Data::Beacon( \"#TARGET: f:{LABEL}\na:b|c:d", 'link' => sub { die 'bad' } );
ok(! $b->parse );
ok( $b->lasterror =~ /^link handler died: bad/, 'dead link handler' );

