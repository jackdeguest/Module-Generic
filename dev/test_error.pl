#!/usr/local/bin/perl
BEGIN
{
	use strict;
	use lib './lib';
	use Module::Generic;
};

{
	my $o = Module::Generic->new;
	$o->error( "Something went wrong." );
	exit( 0 );
}

__END__
