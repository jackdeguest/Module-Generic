#!/usr/local/bin/perl
BEGIN
{
	use strict;
	use lib './lib';
	use Module::Generic;
};

{
	my $err = Module::Generic::Exception->new({ message => "Something went wrong" });
	my $o = Module::Generic::Null->new( $err, { debug => 0 });
	my $rc = $o->get->me->something || die( "$err\n" );
	## my $rc = $o->get->me->something;
	exit( 0 );
}

__END__
