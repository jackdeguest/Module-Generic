#!/usr/local/bin/perl
BEGIN
{
	use strict;
	use lib './lib';
	use Module::Generic;
};

{
	my $hash =
	{
	name => 'Jacques Deguest',
	age => 49,
	location => 'Tokyo',
	properties => [qw( Waseda Paris Mars )],
	};
	my $o = MyObject->new;
	$o->params( $hash );
	print( "Name: ", $o->params->name, "\n" );
	print( "Age: ", $o->params->age, "\n" );
	print( "Location: ", $o->params->location, "\n" );
	print( "Location twice: ", $o->params->location, "\n" );
	foreach my $prop ( @{$o->params->properties} )
	{
		print( "$prop\n" );
	}
	#$o->done( 1 );
	#no overloading;
	#print( "Done value: ", $o->done, "\n" );
	#print( "Got here\n" );
	print( "Calling a non existing object with \$o->settings->branding->logo and this should not crash\n" );
	print( $o->settings->branding->logo, "\n" );
}

package MyObject;
BEGIN
{
	use strict;
	use parent qw( Module::Generic );
};

sub new { return( bless( {} => shift( @_ ) ) ); }

sub params { return( shift->_set_get_hash_as_object( 'params', 'MyObject::Params', @_ ) ); }

sub settings { return( shift->_set_get_object( 'settings', 'MyObject::Settings', @_ ) ); }

__END__

