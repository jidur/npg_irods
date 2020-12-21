package WTSI::NPG::Data::BamDeletionTest;

use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Test::More;
use Test::Exception;
use File::Temp qw( tempdir );
use File::Copy;
use File::Basename;
use Cwd;
use Log::Log4perl;

use WTSI::NPG::iRODS;

use base 'WTSI::NPG::HTS::Test';

Log::Log4perl::init('./etc/log4perl_tests.conf');

my $pid          = $PID;
my $test_counter = 0;
my $collection;
my $samtools_available = `which samtools`;

my @files = qw /f1.bam/;

sub setup_test : Test(setup) { # from Test::Class setup methods are run before every test method
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);
  $collection =
    $irods->add_collection("RunPublisherTest.$pid.$test_counter");

  $test_counter++;

  my $tdir = tempdir( CLEANUP => 1 );
  foreach my $file (@files) {
    my $source = "$tdir/$file";
    `touch $source`;
    my $target = "$collection/$file";
    $irods->add_object($source, $target, $WTSI::NPG::iRODS::CALC_CHECKSUM);
  }

  #copy phix cram file with reads t/data/consent_withdrawn/20131_8#9_phix.cram
  my $example_cram = q[20131_8#9_phix.cram];
  my $example_crai = $example_cram.q[.crai];
  my $data_path = q[t/data/consent_withdrawn];

  foreach my $file ($example_cram, $example_crai){ 
     copy("$data_path/$file","$tdir/$file") or carp "Copy of $file failed: $!";
     $irods->add_object("$tdir/$file","$collection/$file", $WTSI::NPG::iRODS::CALC_CHECKSUM);
     $irods->add_object_avu("$collection/$file", q{sample_consent_withdrawn_email_sent}, 1);
     $irods->add_object_avu("$collection/$file", q{target}, 1);
     $irods->add_object_avu("$collection/$file", q{study},q{mystudy});
     $irods->add_object_avu("$collection/$file", q{rt_ticket},q{12345});
   }
     $irods->add_object_avu("$collection/$example_cram",q{type},q{cram});
     $irods->add_object_avu("$collection/$example_crai",q{type},q{crai});
}

sub teardown_test : Test(teardown) { #from Test::Class, teardown methods are run after every test method 
  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);
  $irods->remove_collection($collection);
}

sub a_object_creation : Test(3){

diag "*** object_creation $test_counter";

  use_ok 'WTSI::NPG::Data::BamDeletion';

  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);
 
  throws_ok { WTSI::NPG::Data::BamDeletion->new(irods => $irods) }
    qr/Attribute \(file\) is required/,
    'constructor should have file attr. defined'; 

  throws_ok { WTSI::NPG::Data::BamDeletion->new(file => q[xyz.cram]) }
    qr/Attribute \(irods\) is required/,
    'constructor should have irods attr. defined';

}


sub b_header : Test(6) {

 SKIP: {
    if (not $samtools_available) {
      skip 'samtools executable not on the PATH', 3;
    }

  my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);


my $tdir = tempdir( CLEANUP => 1 );

diag "*** header $test_counter";
my $file = $irods->get_irods_home . qq[/RunPublisherTest.$pid.1/20131_8#9_phix.cram];
my $bd = WTSI::NPG::Data::BamDeletion->new(irods => $irods,file => $file, outdir => $tdir, rt_ticket => q[111111], dry_run => 0 );
is($bd->file,$file,q[File name found]);

my $header = $bd->_generate_header();
is (ref($header),q[ARRAY],q[ARRAY returned from _generate_header]);

use WTSI::NPG::HTS::HeaderParser;
my $parser = WTSI::NPG::HTS::HeaderParser->new;
is($parser->get_records($header,'SQ'),q[1],q[Header has SQ records]);

is($bd->outdir,$tdir, q[Outdir ok]);

my $path = $tdir.q[/].fileparse($file);
is($bd->_write_header($header),1, q[header file written]);

is(-e $path,'1',q[header file exists]);

$bd->_build_md5sum();
$bd->_reload_file();

} # SKIP samtools

}

sub c_stub : Test(4) {

my $irods = WTSI::NPG::iRODS->new(environment          => \%ENV,
                                    strict_baton_version => 0);

my $file = $irods->get_irods_home . qq[/RunPublisherTest.$pid.1/20131_8#9_phix.cram.crai];
my $tdir = tempdir( CLEANUP => 1 );
my $bd = WTSI::NPG::Data::BamDeletion->new(irods => $irods,file => $file, outdir => $tdir, rt_ticket => q[222222], dry_run => 0);

$bd->process();

my $path = $tdir.q[/].fileparse($file);
is($bd->outfile,$path,q[outfile path generated correctly]);
is($bd->md5_file,$path.q[.md5],q[outfile md5 path generated correctly]);
is($bd->_build_md5sum,q[d41d8cd98f00b204e9800998ecf8427e],q[md5 calculated correctly]);
is(-e $path,'1',q[stub file exists]);

}

