## -*- perl -*-
##----------------------------------------------------------------------------
## Module/Generic.pm
## Version 0.1
## Copyright(c) 2019 Jacques Deguest
## Author: Jacques Deguest <jack@deguest.jp>
## Created 2019/08/24
## Modified 2019/08/25
## All rights reserved.
## 
## This program is free software; you can redistribute it and/or modify it 
## under the same terms as Perl itself.
##----------------------------------------------------------------------------
package Module::Generic;
BEGIN
{
    require 5.6.0;
    use strict;
    use Scalar::Util qw( openhandle );
    use Data::Dumper;
    use Data::Printer 
    {
    	sort_keys => 1,
    	filters => 
    	{
    		'DateTime' => sub{ $_[0]->stringify },
    	}
    };
    use Devel::StackTrace;
	use Class::Struct qw( struct );
	use Text::Number;
	use Number::Format;
    our( @ISA, @EXPORT_OK, @EXPORT, %EXPORT_TAGS, $AUTOLOAD );
    our( $VERSION, $ERROR, $SILENT_AUTOLOAD, $VERBOSE, $DEBUG, $MOD_PERL );
    our( $PARAM_CHECKER_LOAD_ERROR, $PARAM_CHECKER_LOADED, $CALLER_LEVEL );
    our( $OPTIMIZE_MESG_SUB );
    use Exporter ();
    @ISA         = qw( Exporter );
    @EXPORT      = qw( );
    @EXPORT_OK   = qw( subclasses );
    %EXPORT_TAGS = ();
    $VERSION     = '2.0';
    $VERBOSE     = 0;
    $DEBUG       = 0;
    $SILENT_AUTOLOAD      = 1;
    $PARAM_CHECKER_LOADED = 0;
    $CALLER_LEVEL         = 0;
    $OPTIMIZE_MESG_SUB    = 0;
};

{
	## mod_perl/2.0.10
    if( exists( $ENV{ 'MOD_PERL' } )
        &&
        ( $MOD_PERL = $ENV{ 'MOD_PERL' } =~ /^mod_perl\/\d+\.[\d\.]+/ ) )
    {
        select( ( select( STDOUT ), $| = 1 )[ 0 ] );
        require Apache2::Log;
        require Apache2::ServerUtil;
        require Apache2::RequestUtil;
    }
	
	our $DEBUG_LOG_IO = undef();
	
	our $DB_NAME = $DATABASE;
	our $DB_HOST = $SQL_SERVER;
	our $DB_USER = $DB_LOGIN;
	our $DB_PWD  = $DB_PASSWD;
	our $DB_RAISE_ERROR = $SQL_RAISE_ERROR;
	our $DB_AUTO_COMMIT = $SQL_AUTO_COMMIT;

	struct Module::Error => 
	{
	'type'		=> '$',
	'code'		=> '$',
	'message'	=> '$',
	'file'		=> '$',
	'line'		=> '$',
	'package'	=> '$',
	'sub'		=> '$',
	'trace'		=> '$',
	'retry_after' => '$',
	};
}

sub import
{
    my $self = shift( @_ );
    my( $pkg, $file, $line ) = caller();
    local $Exporter::ExportLevel = 1;
    ## local $Exporter::Verbose = $VERBOSE;
    Exporter::import( $self, @_ );
    
    ##print( STDERR "Module::Generic::import(): called from package '$pkg' in file '$file' at line '$line'.\n" ) if( $DEBUG );
    ( my $dir = $pkg ) =~ s/::/\//g;
    my $path  = $INC{ $dir . '.pm' };
    ##print( STDERR "Module::Generic::import(): using primary path of '$path'.\n" ) if( $DEBUG );
    if( defined( $path ) )
    {
        ## Try absolute path name
        $path =~ s/^(.*)$dir\.pm$/$1auto\/$dir\/autosplit.ix/;
        ##print( STDERR "Module::Generic::import(): using treated path of '$path'.\n" ) if( $DEBUG );
        eval
        {
            local $SIG{ '__DIE__' }  = sub{ };
            local $SIG{ '__WARN__' } = sub{ };
            require $path;
        };
        if( $@ )
        {
            $path = "auto/$dir/autosplit.ix";
            eval
            {
                local $SIG{ '__DIE__' }  = sub{ };
				local $SIG{ '__WARN__' } = sub{ };
				require $path;
            };
        }
        if( $@ )
        {
            CORE::warn( $@ ) unless( $SILENT_AUTOLOAD );
        }
        ##print( STDERR "Module::Generic::import(): '$path' ", $@ ? 'not ' : '', "loaded.\n" ) if( $DEBUG );
    }
}

sub new
{
    my $that  = shift( @_ );
    my $class = ref( $that ) || $that;
    ## my $pkg   = ( caller() )[ 0 ];
    ## print( STDERR __PACKAGE__ . "::new(): our calling package is '", ( caller() )[ 0 ], "', our class is '$class'.\n" );
    my $self  = {};
    ## print( STDERR "${class}::OBJECT_READONLY: ", ${ "${class}\::OBJECT_READONLY" }, "\n" );
    if( defined( ${ "${class}\::OBJECT_PERMS" } ) )
    {
        my %hash  = ();
        my $obj   = tie(
        %hash, 
        'Module::Generic::Tie', 
        'pkg'        => [ __PACKAGE__, $class ],
        'perms'        => ${ "${class}::OBJECT_PERMS" },
        );
        $self  = \%hash;
    }
    bless( $self, $class );
    if( $MOD_PERL )
    {
        my $r = Apache2::RequestUtil->request;
        $r->pool->cleanup_register
        (
          sub
          {
          ## my( $pkg, $file, $line ) = caller();
          ## print( STDERR "Apache procedure: Deleting all the object keys for object '$self' and package '$class' called within package '$pkg' in file '$file' at line '$line'.\n" );
          map{ delete( $self->{ $_ } ) } keys( %$self );
          undef( %$self );
          }
        );
    }
    if( defined( ${ "${class}\::LOG_DEBUG" } ) )
    {
    	$self->{ 'log_debug' } = ${ "${class}::LOG_DEBUG" };
    }
    return( $self->init( @_ ) );
}

sub clear
{
	goto( &clear_error );
}

sub clear_error
{
    my $self  = shift( @_ );
    my $class = ref( $self ) || $self;
    my $hash  = $self->_obj2h;
    $hash->{ 'error' } = ${ "$class\::ERROR" } = '';
    return( 1 );
}

sub debug
{
    my $self = shift( @_ );
    my $class = ref( $self );
    my $hash = $self->_obj2h;
    if( @_ )
    {
        my $flag = shift( @_ );
        $hash->{ 'debug' } = $flag;
        $self->message_switch( $flag ) if( $OPTIMIZE_MESG_SUB );
        if( $hash->{ 'debug' } &&
            !$hash->{ 'debug_level' } )
        {
            $hash->{ 'debug_level' } = $hash->{ 'debug' };
        }
    }
    return( $hash->{ 'debug' } || ${"$class\:\:DEBUG"} );
}

sub dumper
{
    my $self  = shift( @_ );
    # local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Useqq = 1;
	local $Data::Dumper::Sortkeys = sub
	{
		my $h = shift( @_ );
		return( [ sort( grep{ ref( $h->{ $_ } ) !~ /^(DateTime|DateTime\:\:)/ } keys( %$h ) ) ] );
	};
    return( Data::Dumper::Dumper( @_ ) );
}

sub printer
{
    my $self = shift( @_ );
    my $opts = {};
    $opts = pop( @_ ) if( scalar( @_ ) > 1 && ref( $_[-1] ) eq 'HASH' );
    if( scalar( keys( %$opts ) ) )
    {
		return( Data::Printer::np( @_, %$opts ) );
    }
    else
    {
		return( Data::Printer::np( @_ ) );
    }
}

*dumpto = \&dumpto_dumper;

sub dumpto_printer
{
    my $self  = shift( @_ );
    my( $data, $file ) = @_;
    my $fh = IO::File->new( ">$file" ) || die( "Unable to create file '$file': $!\n" );
	$fh->binmode( ':utf8' );
	$fh->print( Data::Printer::np( $data ), "\n" );
    $fh->close;
    ## 666 so it can work under command line and web alike
    chmod( 0666, $file );
    return( 1 );
}

sub dumpto_dumper
{
    my $self  = shift( @_ );
    my( $data, $file ) = @_;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Useqq = 1;
    my $fh = IO::File->new( ">$file" ) || die( "Unable to create file '$file': $!\n" );
    if( ref( $data ) )
    {
		$fh->print( Data::Dumper::Dumper( $data ), "\n" );
    }
    else
    {
    	$fh->binmode( ':utf8' );
    	$fh->print( $data );
    }
    $fh->close;
    ## 666 so it can work under command line and web alike
    chmod( 0666, $file );
    return( 1 );
}

sub error
{
	my $self = shift( @_ );
    my $hash  = $self->_obj2h;
	if( @_ )
	{
		my $args = {};
		my $o;
		if( Scalar::Util::blessed( $_[0] ) && $_[0]->isa( 'Module::Error' ) )
		{
			$o = shift( @_ );
		}
		elsif( ref( $_[0] ) eq 'HASH' )
		{
			$args  = shift( @_ );
		}
		else
		{
			my $err = join( '', map( ref( $_ ) eq 'CODE' ? $_->() : $_, @_ ) );
			$args->{ 'message' } = $err;
			$args->{ 'code' } = 500;
			$args->{ 'type' } = 'unknown';
		}
		
		if( !exists( $args->{ 'file' } ) || !exists( $args->{ 'line' } ) )
		{
			my( $frame, $caller ) = ( 0, '' );
			while( $caller = ( caller( $frame ) )[ 0 ] )
			{
				last if( $caller ne 'Module::Generic' );
				$frame++;
			}
			my( $pack, $file, $line ) = caller( $frame );
			my $sub  = ( caller( $frame + 1 ) )[ 3 ];
			my $sub2 = substr( $sub, rindex( $sub, '::' ) + 2 );
			@$args{ qw( package file line sub ) } = ( $pack, $file, $line, $sub2 );
		}
        $args->{ 'message' } = substr( $args->{ 'message' }, 0, $hash->{ 'error_max_length' } ) if( $hash->{ 'error_max_length' } > 0 && length( $args->{ 'message' } ) > $hash->{ 'error_max_length' } );
        my $trace = Devel::StackTrace->new( ignore_package => __PACKAGE__ );
		$args->{ 'trace' } = $trace->as_string;
		if( $o )
		{
			$o->package( $args->{package} );
			$o->file( $args->{file} );
			$o->line( $args->{line} );
			$o->sub( $args->{sub} );
			$o->trace( $args->{trace} );
			$hash->{ 'error' } = ${ $class . '::ERROR' } = $o;
		}
		else
		{
			$hash->{ 'error' } = ${ $class . '::ERROR' } = $o = Module::Error->new( %$args );
		}
		
		if( $hash->{error_handler} && ref( $hash->{error_handler} ) eq 'CODE' )
		{
			$hash->{error_handler}->( $o );
		}
        elsif( $hash->{ 'fatal' } )
        {
            die( sprintf( "Within package %s in file %s at line %d: %s\n", $o->package, $o->file, $o->line, $o->message ) );
        }
        elsif( !exists( $hash->{ 'quiet' } ) || !$hash->{ 'quiet' } )
        {
			warn( $o->message, "\n$trace\n" );
        }
		return( undef() );
	}
	return( $hash->{ 'error' } );
}

sub errno
{
    my $self = shift( @_ );
    if( @_ )
    {
        $self->{ 'errno' } = shift( @_ ) if( $_[ 0 ] =~ /^\d+$/ );
        $self->error( @_ ) if( @_ );
    }
    return( $self->{ 'errno' } );
}

##----{ Used to log an error without risking the script to die.
sub errstr
{
    my $self = shift( @_ );
    my $err  = shift( @_ );
    my $hash = $self->_obj2h;
    if( defined( $err ) )
    {
        $hash->{ 'error' } = $ERROR = $err;
        $self->errors( $err );
        return( undef() );
    }
    return( $hash->{ 'error' } );
}

sub get
{
    my $self = shift( @_ );
    my @data = map{ $self->{ $_ } } @_;
    return( wantarray() ? @data : $data[ 0 ] );
}

sub init
{
    my $self = shift( @_ );
    my $pkg = ref( $self );
    $self->{ 'verbose' } = ${ $pkg . '::VERBOSE' } if( !length( $self->{ 'verbose' } ) );
    $self->{ 'debug' }   = ${ $pkg . '::DEBUG' } if( !length( $self->{ 'debug' } ) );
    $self->{ 'version' } = ${ $pkg . '::VERSION' } if( !defined( $self->{ 'version' } ) );
    $self->{ 'level' }   = 0;
    ## If no debug level was provided when calling message, this level will be assumed
    ## Example: message( "Hello" );
    ## If _message_default_level was set to 3, this would be equivalent to message( 3, "Hello" )
    $self->{ '_message_default_level' } = 0;
    if( @_ )
    {
    	my @args = @_;
    	my $vals;
    	if( ref( $args[0] ) eq 'HASH' )
    	{
    		## $self->_message( 3, "Got an hash ref" );
    		my $h = shift( @args );
    		$vals = [ %$h ];
    		## $vals = [ %{$_[0]} ];
    	}
    	elsif( ref( $args[0] ) eq 'ARRAY' )
    	{
    		## $self->_message( 3, "Got an array ref" );
    		$vals = $args[0];
    	}
    	## Special case when there is an undefined value passed (null) even though it is declared as a hash or object
    	elsif( scalar( @args ) == 1 && !defined( $args[0] ) )
    	{
    		return( undef() );
    	}
    	elsif( ( scalar( @args ) % 2 ) )
    	{
    		return( $self->error( sprintf( "Uneven number of parameters provided (%d). Should receive key => value pairs. Parameters provideds are: %s", scalar( @args ), join( ', ', @args ) ) ) );
    	}
    	else
    	{
    		## $self->message( 3, "Got an array: ", sub{ $self->dumper( \@args ) } );
    		$vals = \@args;
    	}
    	for( my $i = 0; $i < scalar( @$vals ); $i++ )
    	{
    		my $name = $vals->[ $i ];
    		my $val  = $vals->[ ++$i ];
    		if( exists( $self->{ $name } ) )
    		{
    			if( index( $self->{ $name }, '::' ) != -1 )
    			{
    				my $thisPack = $self->{ $name };
    				if( !Scalar::Util::blessed( $val ) )
    				{
    					return( $self->error( "$name parameter expects a package $thisPack object, but instead got '$val'." ) );
    				}
    				elsif( !$val->isa( $thisPack ) )
    				{
    					return( $self->error( "$name parameter expects a package $thisPack object, but instead got an object from package '", ref( $val ), "'." ) );
    				}
    			}
    			elsif( $self->{_init_strict} )
    			{
    				if( ref( $self->{ $name } ) eq 'ARRAY' )
    				{
    					return( $self->error( "$name parameter expects an array reference, but instead got '$val'." ) ) if( ref( $val ) ne 'ARRAY' );
    				}
    				elsif( ref( $self->{ $name } ) eq 'HASH' )
    				{
    					return( $self->error( "$name parameter expects an hash reference, but instead got '$val'." ) ) if( ref( $val ) ne 'HASH' );
    				}
    				elsif( ref( $self->{ $name } ) eq 'SCALAR' )
    				{
    					return( $self->error( "$name parameter expects a scalar reference, but instead got '$val'." ) ) if( ref( $val ) ne 'SCALAR' );
    				}
    			}
    		}
    		## The name parameter does not exist
    		else
    		{
    			## If we are strict, we reject
    			next if( $self->{_init_strict} );
    		}
    		## We passed all tests
    		$self->{ $name } = $val;
    	}
    }
    if( $OPTIMIZE_MESG_SUB && !$self->{ 'verbose' } && !$self->{ 'debug' } )
    {
        if( defined( &{ "$pkg\::message" } ) )
        {
            *{ "$pkg\::message_off" } = \&{ "$pkg\::message" } unless( defined( &{ "$pkg\::message_off" } ) );
            *{ "$pkg\::message" } = sub { 1 };
        }
    }
    return( $self );
}

sub log
{
	my $self = shift( @_ );
	my $io   = $self->log_io;
	#print( STDERR "Module::Generic::log: \$io now is '$io'\n" );
	return( undef() ) if( !$io );
	#print( STDERR "Module::Generic::log: \$io is not an open handle\n" ) if( !openhandle( $io ) && $io );
	return( undef() ) if( !Scalar::Util::openhandle( $io ) && $io );
	## 2019-06-14: I decided to remove this test, because if a log is provided it should print to it
	## If we are on the command line, we can easily just do tail -f log_file.txt for example and get the same result as
	## if it were printed directly on the console
# 	my $rc = CORE::print( $io @_ ) || return( $self->error( "Unable to print to log file: $!" ) );
	my $rc = $io->print( @_ ) || return( $self->error( "Unable to print to log file: $!" ) );
	## print( STDERR "Module::Generic::log (", ref( $self ), "): successfully printed to debug log file. \$rc is $rc, \$io is '$io' and message is: ", join( '', @_ ), "\n" );
	return( $rc );
}

sub log_io
{
	#return( shift->_set_get( 'log_io', @_ ) );
	my $self = shift( @_ );
	my $class = ref( $self );
	if( @_ )
	{
		my $io = shift( @_ );
		$self->_set_get( 'log_io', $io );
	}
	elsif( ${ "${class}::LOG_DEBUG" } && 
		!$self->_set_get( 'log_io' ) && 
		${ "${class}::DEB_LOG" } )
	{
		our $DEB_LOG = ${ "${class}::DEB_LOG" };
		unless( $DEBUG_LOG_IO )
		{
			$DEBUG_LOG_IO = IO::File->new( ">>$DEB_LOG" ) || die( "Unable to open debug log file $DEB_LOG in append mode: $!\n" );
			$DEBUG_LOG_IO->binmode( ':utf8' );
			$DEBUG_LOG_IO->autoflush( 1 );
		}
		$self->_set_get( 'log_io', $DEBUG_LOG_IO );
	}
	return( $self->_set_get( 'log_io' ) );
}

sub log4perl
{
	my $self = shift( @_ );
	if( @_ )
	{
		require Log::Log4perl;
		my $ref = shift( @_ );
		Log::Log4perl::init( $ref->{ 'config_file' } );
		my $log = Log::Log4perl->get_logger( $ref->{ 'domain' } );
		$self->{ 'log4perl' } = $log;
	}
	else
	{
		$self->{ 'log4perl' };
	}
}

sub message
{
    my $self = shift( @_ );
    my $class = ref( $self ) || $self;
    ## my( $pack, $file, $line ) = caller;
    my $hash = $self->_obj2h;
    ## print( STDERR __PACKAGE__ . "::message(): Called from package $pack in file $file at line $line with debug value '$hash->{debug}', package DEBUG value '", ${ $class . '::DEBUG' }, "' and params '", join( "', '", @_ ), "'\n" );
    if( $hash->{ 'verbose' } || $hash->{ 'debug' } || ${ $class . '::DEBUG' } )
    {
        my $ref;
        $ref = $self->message_check( @_ );
    	## print( STDERR __PACKAGE__ . "::message(): message_check() returns '$ref' (", join( '', @$ref ), ")\n" );
        ## return( 1 ) if( !( $ref = $self->message_check( @_ ) ) );
        return( 1 ) if( !$ref );
        ## By now, we should have a reference to @_ in $ref
        ## my $class = ref( $self ) || $self;
        my $stackFrame = $self->message_frame( (caller(1))[3] ) || 1;
        $stackFrame = 1 unless( $stackFrame =~ /^\d+$/ );
        $stackFrame-- if( $stackFrame );
        my( $pkg, $file, $line, @otherInfo ) = caller( $stackFrame );
        my $sub = ( caller( $stackFrame + 1 ) )[3];
        my $sub2 = substr( $sub, rindex( $sub, '::' ) + 2 );
        if( ref( $self->{ '_message_frame' } ) eq 'HASH' )
        {
        	if( exists( $self->{ '_message_frame' }->{ $sub2 } ) )
        	{
        		my $frameNo = int( $self->{ '_message_frame' }->{ $sub2 } );
        		if( $frameNo > 0 )
        		{
        			( $pkg, $file, $line, $sub ) = caller( $frameNo );
					$sub2 = substr( $sub, rindex( $sub, '::' ) + 2 );
        		}
        	}
        }
        if( $sub2 eq 'message' )
        {
            $stackFrame++;
            ( $pkg, $file, $line, @otherInfo ) = caller( $stackFrame );
			my $sub = ( caller( $stackFrame + 1 ) )[3];
            $sub2 = substr( $sub, rindex( $sub, '::' ) + 2 );
        }
        my $txt = join( '', map( ref( $_ ) eq 'CODE' ? $_->() : $_, @$ref ) );
        my $mesg = "${class}::${sub2}() [$line]: " . $txt;
        $mesg    =~ s/\n$//gs;
        $mesg = '## ' . join( "\n## ", split( /\n/, $mesg ) );
        ## If Mod perl is activated AND we are not using a private log
        if( $MOD_PERL && !${ "${class}::LOG_DEBUG" } )
        {
			require Apache2::ServerUtil;
			my $s = Apache2::ServerUtil->server;
        	$s->log_error( $mesg );
			## $r->rflush;
        }
        ## Should we log message in database?
        elsif( !-t( STDIN ) && ${ $class . '::LOG2DB' } && $self->__dbh )
        {
        	return( $self->message_sql({
        		'message'	=> $txt,
        		'file'		=> $file,
        		'line'		=> $line,
        		'package'	=> $class,
        		'sub'		=> $sub2,
        		'level'		=> ( $_[0] =~ /^\d+$/ ? $_[0] : 0 ),
        	}) );
        }
        elsif( !-t( STDIN ) && ${ $class . '::MESSAGE_HANDLER' } && ref( ${ $class . '::MESSAGE_HANDLER' } ) eq 'CODE' )
        {
        	my $h = ${ $class . '::MESSAGE_HANDLER' };
        	$h->({
        		'message'	=> $txt,
        		'file'		=> $file,
        		'line'		=> $line,
        		'package'	=> $class,
        		'sub'		=> $sub2,
        		'level'		=> ( $_[0] =~ /^\d+$/ ? $_[0] : 0 ),
        	});
        }
        ## Or maybe then into a private log file?
        ## This way, even if the log method is superseeded, we can keep using ours without interfering with the other one
        elsif( &log( $self, $mesg, "\n" ) )
        {
        	return( 1 );
        }
        ## Otherwise just on the stderr
        else
        {
			my $err = IO::File->new;
			$err->fdopen( fileno( STDERR ), 'w' );
			$err->binmode( ":utf8" );
			$err->autoflush( 1 );
			$err->print( $mesg, "\n" );
        }
    }
    return( 1 );
}

sub messagef
{
	my $self = shift( @_ );
    my $class = ref( $self ) || $self;
    my $hash = $self->_obj2h;
    if( $hash->{ 'verbose' } || $hash->{ 'debug' } || ${ $class . '::DEBUG' } )
    {
    	my $level = ( $_[0] =~ /^\d+$/ ? shift( @_ ) : undef() );
        my $ref = \@_;
        my $fmt = shift( @$ref );
        my $txt = sprintf( $fmt, map( ref( $_ ) eq 'CODE' ? $_->() : $_, @$ref ) );
        return( $self->message( defined( $level ) ? ( $level, $txt ) : $txt ) );
    }
    return( 1 );
}

sub message_check
{
    my $self  = shift( @_ );
    my $class = ref( $self ) || $self;
    my $hash = $self->_obj2h;
    ## printf( STDERR "Our class is $class and DEBUG_TARGET contains: '%s' and debug value is %s\n", join( ', ', @${ "${class}::DEBUG_TARGET" } ), $hash->{ 'debug' } );
    if( @_ )
    {
    	if( $_[0] !~ /^\d/ )
    	{
    		if( $self->{ '_message_default_level' } =~ /^\d+$/ &&
    			$self->{ '_message_default_level' } > 0 )
			{
				unshift( @_, $self->{ '_message_default_level' } );
			}
			else
			{
				unshift( @_, 1 );
			}
		}
        ## If the first argument looks line a number, and there is more than 1 argument
        ## and it is greater than 1, and greater than our current debug level
        ## well, we do not output anything then...
        if( $_[ 0 ] =~ /^\d+$/ && @_ > 1 )
        {
        	my $target_re = '';
        	if( ref( ${ "${class}::DEBUG_TARGET" } ) eq 'ARRAY' )
        	{
				$target_re = scalar( @${ "${class}::DEBUG_TARGET" } ) ? join( '|', @${ "${class}::DEBUG_TARGET" } ) : '';
        	}
        	if( $hash->{debug} >= $_[0] ||
        		$hash->{verbose} >= $_[0] ||
        		${ $class . '::DEBUG' } >= $_[0] ||
        		$hash->{ 'debug_level' } >= $_[0] ||
        		$hash->{debug} >= 100 || 
        		( length( $target_re ) && $class =~ /^$target_re$/ && ${ $class . '::GLOBAL_DEBUG' } >= $_[0] ) )
        	{
        		## print( STDERR ref( $self ) . "::message_check(): debug is '$hash->{debug}', verbose '$hash->{verbose}', DEBUG '", ${ $class . '::DEBUG' }, "', debug_level = $hash->{debug_level}\n" );
				shift( @_ );
                if( ref( $_[0] ) eq 'CODE' )
                {
                	my $this = $_[0]->();
                	return( [ $this ] );
                }
                else
                {
					return( \@_ );
                }
        	}
        	else
        	{
        		return( 0 );
        	}
        }
    }
    return( 0 );
}

sub message_frame
{
    my $self = shift( @_ );
    $self->{ '_message_frame' } = {} if( !exists( $self->{ '_message_frame' } ) );
    my $mf = $self->{ '_message_frame' };
    if( @_ )
    {
    	my $args = {};
    	if( ref( $_[0] ) eq 'HASH' )
    	{
    		$args = shift( @_ );
    		my @k = keys( %$args );
    		@$mf{ @k } = @$args{ @k };
    	}
    	elsif( !( @_ % 2 ) )
    	{
    		$args = { @_ };
    		my @k = keys( %$args );
    		@$mf{ @k } = @$args{ @k };
    	}
    	elsif( scalar( @_ ) == 1 )
    	{
    		my $sub = shift( @_ );
			$sub = substr( $sub, rindex( $sub, '::' ) + 2 ) if( index( $sub, '::' ) != -1 );
    		return( $mf->{ $sub } );
    	}
    	else
    	{
    		return( $self->error( "I was expecting a key => value pair such as routine => stack frame (integer)" ) );
    	}
    }
    return( $mf );
}

sub message_sql
{
    my $self = shift( @_ );
    my $hash = shift( @_ ) || return( $self->error( "No information to log was passed." ) );
    my $dbh  = $self->__dbh->clone;
    $hash->{ 'type' } ||= 'info';
    my $query = <<EOT;
INSERT INTO log (type, message, file, line, package, sub, level) VALUES(?, ?, ?, ?, ?, ?, ?)
EOT
	my $sth = $dbh->prepare_cached( $query ) || return( $self->error( sprintf( "Unable to prepare sql query to log message: %s\n%s", $dbh->errstr, $query ) ) );
	$sth->execute( @$hash{ qw( type message file line package sub level ) } ) || return( $self->error( sprintf( "Unable to execute sql query to log message: %s\n%s", $dbh->errstr, $query ) ) );
	my $id = $dbh->last_insert_id( undef, undef, 'log', undef );
	$sth->finish;
	return( $id );
}

sub message_switch
{
    my $self = shift( @_ );
    my $pkg  = ref( $self ) || $self;
    if( @_ )
    {
        my $flag = shift( @_ );
        if( $flag )
        {
            if( defined( &{ "$pkg\::message_off" } ) )
            {
            	## Restore previous backup
                *{ "${pkg}::message" } = \&{ "${pkg}::message_off" };
            }
            else
            {
                *{ "${pkg}::message" } = \&{ "Module::Generic::message" };
            }
        }
        ## We switch it down if nobody is going to use it
        elsif( !$flag && !$self->{ 'verbose' } && !$self->{ 'debug' } )
        {
            *{ "${pkg}::message_off" } = \&{ "${pkg}::message" } unless( defined( &{ "${pkg}::message_off" } ) );
            *{ "${pkg}::message" } = sub { 1 };
        }
    }
    return( 1 );
}

sub param
{
    my $self = shift( @_ );
    if( @_ )
    {
        if( @_ == 1 )
        {
            return( $self->{ $_[ 0 ] } );
        }
        elsif( !( @_ % 2 ) )
        {
            for( my $i = 0; $i < @_; $i += 2 )
            {
                my( $opt, $val ) = @_[ $i, $i + 1 ];
				if( $self->can( $opt ) )
				{
					return( undef() ) if( !defined( $self->$opt( $val ) ) );
				}
				elsif( exists( $self->{ $opt } ) )
				{
					$self->{ $opt } = $val;
				}
				else
				{
					return( $self->error( "Unsupported parameter \"$opt\" ($val)." ) );
				}
            }
            return( 1 );
        }
    }
    return;
}

sub quiet {	return( shift->_set_get( 'quiet', @_ ) ); }

sub save
{
	my $self = shift( @_ );
	my $opts = {};
	$opts = pop( @_ ) if( ref( $_[-1] ) eq 'HASH' );
	my( $file, $data );
	if( @_ == 2 )
	{
		$opts->{data} = shift( @_ );
		$opts->{file} = shift( @_ );
	}
	return( $self->error( "No file was provided to save data to." ) ) if( !$opts->{file} );
	my $fh = IO::File->new( ">$opts->{file}" ) || return( $self->error( "Unable to open file \"$opts->{file}\" in write mode: $!" ) );
	$fh->binmode( ':' . $opts->{encoding} ) if( $opts->{encoding} );
	$fh->autoflush( 1 );
	if( !defined( $fh->print( ref( $opts->{data} ) eq 'SCALAR' ? ${$opts->{data}} : $opts->{data} ) ) )
	{
		return( $self->error( "Unable to write data to file \"$opts->{file}\": $!" ) )
	}
	$fh->close;
	my $bytes = -s( $opts->{file} );
	return( $bytes );
}

sub set
{
    my $self = shift( @_ );
    my %arg  = ();
    if( @_ )
    {
        %arg = ( @_ );
        my $hash = $self->_obj2h;
        my @keys = keys( %arg );
        @$hash{ @keys } = @arg{ @keys };
    }
    return( scalar( keys( %arg ) ) );
}

sub subclasses
{
    my $self  = shift( @_ );
    my $that  = '';
    $that     = @_ ? shift( @_ ) : $self;
    my $base  = ref( $that ) || $that;
    $base  =~ s,::,/,g;
    $base .= '.pm';
    
    require IO::Dir;
    ## remove '.pm'
    my $dir = substr( $INC{ $base }, 0, ( length( $INC{ $base } ) ) - 3 );
    
    my @packages = ();
    my $io = IO::Dir->open( $dir );
    if( defined( $io ) )
    {
        @packages = map{ substr( $_, 0, length( $_ ) - 3 ) } grep{ substr( $_, -3 ) eq '.pm' && -f( "$dir/$_" ) } $io->read();
        $io->close ||
        warn( "Unable to close directory \"$dir\": $!\n" );
    }
    else
    {
        warn( "Unable to open directory \"$dir\": $!\n" );
    }
    return( wantarray() ? @packages : \@packages );
}

sub verbose
{
    my $self = shift( @_ );
    my $hash = $self->_obj2h;
    if( @_ )
    {
        my $flag = shift( @_ );
        $hash->{ 'verbose' } = $flag;
        $self->message_switch( $flag ) if( $OPTIMIZE_MESG_SUB );
    }
    return( $hash->{ 'verbose' } );
}

sub will
{
    ( @_ >= 2 && @_ <= 3 ) || die( 'Usage: $obj->can( "method" ) or Module::Generic::will( $obj, "method" )' );
    my( $obj, $meth, $level );
    ## $obj->will( $other_obj, 'method' );
    if( @_ == 3 && ref( $_[ 1 ] ) )
    {
        $obj  = $_[ 1 ];
        $meth = $_[ 2 ];
    }
    else
    {
        ( $obj, $meth, $level ) = @_;
    }
    return( undef() ) if( !ref( $obj ) && index( $obj, '::' ) == -1 );
    ## Give a chance to UNIVERSAL::can
    my $ref = undef;
    if( Scalar::Util::blessed( $obj ) && ( $ref = $obj->can( $meth ) ) )
    {
    	return( $ref );
    }
    my $class = ref( $obj ) || $obj;
    my $origi = $class;
    if( index( $meth, '::' ) != -1 )
    {
        $origi = substr( $meth, 0, rindex( $meth, '::' ) );
        $meth  = substr( $meth, rindex( $meth, '::' ) + 2 );
    }
    $ref = \&{ "$class\::$meth" } if( defined( &{ "$class\::$meth" } ) );
    ## print( $err "\t" x $level, "UNIVERSAL::can ", defined( $ref ) ? "succeeded" : "failed", " in finding the method \"$meth\" in object/class $obj.\n" );
    ## print( $err "\t" x $level, defined( $ref ) ? "succeeded" : "failed", " in finding the method \"$meth\" in object/class $obj.\n" );
    return( $ref ) if( defined( $ref ) );
    ## We do not go further down the rabbit hole if level is greater or equal to 10
    $level ||= 0;
    return( undef() ) if( $level >= 10 );
    $level++;
    ## Let's see what Alice has got for us... :-)
    ## We look in the @ISA to see if the method exists in the package from which we
    ## possibly inherited
    if( @{ "$class\::ISA" } )
    {
        ## print( STDERR "\t" x $level, "Checking ", scalar( @{ "$class\::ISA" } ), " entries in \"\@${class}\:\:ISA\".\n" );
        foreach my $pack ( @{ "$class\::ISA" } )
        {
            ## print( STDERR "\t" x $level, "Looking up method \"$meth\" in inherited package \"$pack\".\n" );
            my $ref = &will( $pack, "$origi\::$meth", $level );
            return( $ref ) if( defined( $ref ) );
        }
    }
    ## Then, maybe there is an AUTOLOAD to trap undefined routine?
    ## But, we do not want any loop, do we?
    ## Since will() is called from Module::Generic::AUTOLOAD to check if EXTRA_AUTOLOAD exists
    ## we are not going to call Module::Generic::AUTOLOAD for EXTRA_AUTOLOAD...
    if( $class ne 'Module::Generic' && $meth ne 'EXTRA_AUTOLOAD' && defined( &{ "$class\::AUTOLOAD" } ) )
    {
        ## print( STDERR "\t" x ( $level - 1 ), "Found an AUTOLOAD in class \"$class\". Ok.\n" );
        my $sub = sub
        {
            $class::AUTOLOAD = "$origi\::$meth";
            &{ "$class::AUTOLOAD" }( @_ );
        };
        return( $sub );
    }
    return( undef() );
}

sub _instantiate_object
{
	my $self = shift( @_ );
    my $field = shift( @_ );
    my $class = shift( @_ );
	my $o = @_ ? $class->new( @_ ) : $class->new;
	$o->debug( $self->{debug} ) if( $o->can( 'debug' ) );
	return( $self->error( "Unable to instantiate an object of class $class: ", $class->error ) ) if( !defined( $o ) );
	return( $o );
}

sub _obj2h
{
    my $self = shift( @_ );
    ## print( STDERR "_obj2h(): Getting a hash refernece out of the object '$self'\n" );
    if( UNIVERSAL::isa( $self, 'HASH' ) )
    {
        return( $self );
    }
    elsif( UNIVERSAL::isa( $self, 'GLOB' ) )
    {
    	## print( STDERR "Returning a reference to an hash for glob $self\n" );
        return( \%{*$self} );
    }
    ## The method that called message was itself called using the package name like My::Package->some_method
    ## We are going to check if global $DEBUG or $VERBOSE variables are set and create the related debug and verbose entry into the hash we return
    elsif( !ref( $self ) )
    {
    	my $class = $self;
    	my $hash =
    	{
    	'debug' => ${ "${class}\::DEBUG" },
    	'verbose' => ${ "${class}\::VERBOSE" },
    	'error' => ${ "${class}\::ERROR" },
    	};
    	## XXX 
    	## print( STDERR "Called with '$self' with debug value '$hash->{debug}' and verbose '$hash->{verbose}'\n" );
    	return( $hash );
    }
    ## Because object may be accessed as My::Package->method or My::Package::method
    ## there is not always an object available, so we need to fake it to avoid error
    ## This is primarly itended for generic methods error(), errstr() to work under any conditions.
    else
    {
        return( {} );
    }
}

sub _set_get
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    my $hash  = $self->_obj2h;
    if( @_ )
    {
        my $val = ( @_ == 1 ) ? shift( @_ ) : [ @_ ];
        $hash->{ $field } = $val;
    }
    if( wantarray() )
    {
        if( ref( $hash->{ $field } ) eq 'ARRAY' )
        {
            return( @{ $hash->{ $field } } );
        }
        elsif( ref( $hash->{ $field } ) eq 'HASH' )
        {
            return( %{ $hash->{ $field } } );
        }
        else
        {
            return( ( $hash->{ $field } ) );
        }
    }
    else
    {
        return( $hash->{ $field } );
    }
}

sub _set_get_datetime
{
	my $self = shift( @_ );
    my $field = shift( @_ );
	if( @_ )
	{
		my $time = shift( @_ );
		if( !defined( $time ) )
		{
			$self->{ $field } = $time;
			return( $self->{ $field } );
		}
		elsif( Scalar::Util::blessed( $time ) )
		{
			return( $self->error( "Object provided as value for $field, but this is not a DateTime object" ) ) if( $time->isa( 'DateTime' ) );
			$self->{ $field } = $time;
			return( $self->{ $field } );
		}
		elsif( $time !~ /^\d{10}$/ )
		{
			return( $self->error( "DateTime value ($time) provided for field $field does not look like a unix timestamp" ) );
		}
		
		my $now;
		eval
		{
			require DateTime;
			$now = DateTime->from_epoch(
				epoch => $time,
				time_zone => 'local',
			);
		};
		if( $@ )
		{
			$self->_message( "Error while trying to get the DateTime object for field $k with value $time" );
		}
		else
		{
			$self->_message( 3, "Returning the DateTime object '$now'" );
			$self->{ $field } = $now;
		}
	}
	return( $self->{ $field } );
}

sub _set_get_scalar
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    if( @_ )
    {
        my $val = ( @_ == 1 ) ? shift( @_ ) : join( '', @_ );
        ## Just in case, we force stringification
        ## $val = "$val" if( defined( $val ) );
        return( $self->error( "Method $field takes only a scalar, but value provided ($val) is a reference" ) ) if( ref( $val ) eq 'HASH' || ref( $val ) eq 'ARRAY' );
        $self->{ $field } = $val;
    }
	return( $self->{ $field } );
}

sub _set_get_scalar_or_object
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    my $class = shift( @_ );
    if( @_ )
    {
    	if( ref( $_[0] ) eq 'HASH' || Scalar::Util::blessed( $_[0] ) )
    	{
    		return( $self->_set_get_object( $field, $class, @_ ) );
    	}
    	else
    	{
    		return( $self->_set_get_scalar( $field, @_ ) );
    	}
    }
	return( $self->{ $field } );
}

sub _set_get_array
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    if( @_ )
    {
        my $val = ( @_ == 1 ) ? shift( @_ ) : [ @_ ];
        $self->{ $field } = $val;
    }
	return( $self->{ $field } );
}

sub _set_get_hash
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    if( @_ )
    {
        my $val;
        if( ref( $_[0] ) eq 'HASH' )
        {
        	$val = shift( @_ );
        }
        elsif( ( @_ % 2 ) )
        {
        	$val = { @_ };
        }
        else
        {
        	my $val = shift( @_ );
        	return( $self->error( "Method $field takes only a hash or reference to a hash, but value provided ($val) is not supported" ) );
        }
        $self->{ $field } = $val;
    }
	return( $self->{ $field } );
}

sub _set_get_number
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    if( @_ )
    {
    	$self->{ $field } = Text::Number->new( shift( @_ ) );
    }
    return( $self->{ $field } );
}

sub _set_get_number_or_object
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    my $class = shift( @_ );
    if( @_ )
    {
    	if( ref( $_[0] ) eq 'HASH' || Scalar::Util::blessed( $_[0] ) )
    	{
    		return( $self->_set_get_object( $field, $class, @_ ) );
    	}
    	else
    	{
    		return( $self->_set_get_number( $field, @_ ) );
    	}
    }
    return( $self->{ $field } );
}

sub _set_get_object
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    my $class = shift( @_ );
    no overloading;
    if( @_ )
    {
    	if( scalar( @_ ) == 1 )
    	{
    		## User removed the value by passing it an undefined value
    		if( !defined( $_[0] ) )
    		{
    			$self->{ $field } = undef();
    		}
			## User pass an object
    		elsif( Scalar::Util::blessed( $_[0] ) )
    		{
				my $o = shift( @_ );
				return( $self->error( "Object provided for $field is not a valid $class object" ) ) if( !$o->isa( "$class" ) );
				$o->debug( $self->{debug} ) if( $o->can( 'debug' ) );
				$self->{ $field } = $o;
    		}
    		else
    		{
				my $o = $self->_instantiate_object( $field, $class, @_ );
				$self->_message( 3, "Setting field $field value to $o" );
				$self->{ $field } = $o;
    		}
    	}
    	else
    	{
			my $o = $self->_instantiate_object( $field, $class, @_ );
			$self->_message( 3, "Setting field $field value to $o" );
			$self->{ $field } = $o;
    	}
    }
	return( $self->{ $field } );
}

sub _set_get_object_variant
{
	my $self = shift( @_ );
    my $field = shift( @_ );
    ## The class precisely depends on what we find looking ahead
    my $class = shift( @_ );
	if( @_ )
	{
		if( ref( $_[0] ) eq 'HASH' )
		{
			my $o = $self->_instantiate_object( $field, $class, @_ );
		}
		## AN array of objects hash
		elsif( ref( $_[0] ) eq 'ARRAY' )
		{
			my $arr = shift( @_ );
			my $res = [];
			foreach my $data ( @$arr )
			{
				my $o = $self->_instantiate_object( $field, $class, $data ) || return( $self->error( "Unable to create object: ", $self->error ) );
				push( @$res, $o );
			}
			$self->{ $field } = $res;
		}
	}
	return( $self->{ $field } );
}

sub _set_get_uri
{
    my $self  = shift( @_ );
    my $field = shift( @_ );
    if( @_ )
    {
		my $str = shift( @_ );
		if( Scalar::Util::blessed( $str ) && $str->isa( 'URI' ) )
		{
			$self->{ $field } = $str;
		}
		elsif( defined( $str ) && ( $str =~ /^[a-z]+:\/{2}/ || $str =~ /^urn\:[a-z]+\:/ || $str =~ /^[a-z]+\:/ ) )
		{
			$self->{ $field } = URI->new( $str );
			warn( "URI subclass is missing to handle this specific URI '$str'\n" ) if( !$self->{ $field }->has_recognized_scheme );
		}
		elsif( defined( $str ) )
		{
			return( $self->error( "URI value provided '$str' does not look like an URI, so I do not know what to do with it." ) );
		}
		else
		{
			$self->{ $field } = undef();
		}
    }
    return( $self->{ $field } );
}

sub __dbh
{
    my $self = shift( @_ );
    my $class = ref( $self ) || $self;
    my $hash = $self->_obj2h;
	if( !$hash->{ '__dbh' } )
	{
		return( '' ) if( !${ "$class\::DB_DSN" } );
		use DBI;
		## Connecting to database
		my $db_opt = {};
		$db_opt->{RaiseError} = ${ "$class\::DB_RAISE_ERROR" } if( length( ${ "$class\::DB_RAISE_ERROR" } ) );
		$db_opt->{AutoCommit} = ${ "$class\::DB_AUTO_COMMIT" } if( length( ${ "$class\::DB_AUTO_COMMIT" } ) );
		$db_opt->{PrintError} = ${ "$class\::DB_PRINT_ERROR" } if( length( ${ "$class\::DB_PRINT_ERROR" } ) );
		$db_opt->{ShowErrorStatement} = ${ "$class\::DB_SHOW_ERROR_STATEMENT" } if( length( ${ "$class\::DB_SHOW_ERROR_STATEMENT" } ) );
		$db_opt->{client_encoding} = ${ "$class\::DB_CLIENT_ENCODING" } if( length( ${ "$class\::DB_CLIENT_ENCODING" } ) );
		my $dbh = DBI->connect_cached( ${ "$class\::DB_DSN" } ) ||
		die( "Unable to connect to sql database with dsn '", ${ "$class\::DB_DSN" }, "'\n" );
		$dbh->{pg_server_prepare} = 1 if( ${ "$class\::DB_SERVER_PREPARE" } );
		$hash->{ '__dbh' } = $dbh;
	}
	return( $hash->{ '__dbh' } );
}

sub DEBUG
{
    my $self = shift( @_ );
    my $pkg  = ref( $self ) || $self;
    return( ${ $pkg . '::DEBUG' } );
}

sub VERBOSE
{
    my $self = shift( @_ );
    my $pkg  = ref( $self ) || $self;
    return( ${ $pkg . '::VERBOSE' } );
}

AUTOLOAD
{
    my $self;
    $self = shift( @_ ) if( ref( $_[ 0 ] ) && index( ref( $_[ 0 ] ), 'Module::' ) != -1 );
    my( $class, $meth );
    $class = ref( $self ) || $self;
    ## Leave this commented out as we need it a little bit lower
    my( $pkg, $file, $line ) = caller();
    my $sub = ( caller( 1 ) )[ 3 ];
    no overloading;
    if( $sub eq 'Module::Generic::AUTOLOAD' )
    {
    	my $mesg = "Module::Generic::AUTOLOAD (called at line '$line') is looping for autoloadable method '$AUTOLOAD' and args '" . join( "', '", @_ ) . "'.";
        if( $MOD_PERL )
        {
        	my $r = Apache2::RequestUtil->request;
        	$r->log_error( $mesg );
        }
        else
        {
			print( $err $mesg, "\n" );
        }
        exit( 0 );
    }
    $meth  = $AUTOLOAD;
    if( CORE::index( $meth, '::' ) != -1 )
    {
        my $idx = rindex( $meth, '::' );
        $class = substr( $meth, 0, $idx );
        $meth  = substr( $meth, $idx + 2 );
    }
    
    if( $self && $self->can( 'autoload' ) )
    {
    	if( my $code = $self->autoload( $meth ) )
    	{
    		return( $code->( $self ) ) if( $code );
    	}
    }
    
    $meth = lc( $meth );
    my $hash = '';
    $hash    = $self->_obj2h if( defined( $self ) );
    ## CORE::print( STDERR "Storing '$meth' with value ", join( ', ', @_ ), "\n" );
    if( $hash && CORE::exists( $hash->{ $meth } ) )
    {
        if( @_ )
        {
            my $val = ( @_ == 1 ) ? shift( @_ ) : [ @_ ];
            $hash->{ $meth } = $val;
        }
        if( wantarray() )
        {
            if( ref( $hash->{ $meth } ) eq 'ARRAY' )
            {
                return( @{ $hash->{ $meth } } );
            }
            elsif( ref( $hash->{ $meth } ) eq 'HASH' )
            {
                return( %{ $hash->{ $meth } } );
            }
            else
            {
                return( ( $hash->{ $meth } ) );
            }
        }
        else
        {
            return( $hash->{ $meth } );
        }
    }
    ## Because, if it does not exist in the caller's package, 
    ## calling the method will get us here infinitly,
    ## since UNIVERSAL::can will somehow return true even if it does not exist
    elsif( $self && $self->can( $meth ) && defined( &{ "$class\::$meth" } ) )
    {
        return( $self->$meth( @_ ) );
    }
    elsif( defined( &$meth ) )
    {
        no strict 'refs';
        *$meth = \&$meth;
        return( &$meth( @_ ) );
    }
    else
    {
        my $sub = $AUTOLOAD;
        my( $pkg, $func ) = ( $sub =~ /(.*)::([^:]+)$/ );
        my $mesg = "Module::Generic::AUTOLOAD(): Searching for routine '$func' from package '$pkg'.";
        if( $MOD_PERL )
        {
        	my $r = Apache2::RequestUtil->request;
        	$r->log_error( $mesg );
        }
        else
        {
			print( STDERR $mesg . "\n" ) if( $DEBUG );
        }
        $pkg =~ s/::/\//g;
        if( defined( $filename = $INC{ "$pkg.pm" } ) )
        {
            $filename =~ s/^(.*)$pkg\.pm\z/$1auto\/$pkg\/$func.al/s;
            ## print( STDERR "Found possible autoloadable file '$filename'.\n" );
            if( -r( $filename ) )
            {
                unless( $filename =~ m|^/|s )
                {
                    $filename = "./$filename";
                }
            }
            else
            {
                $filename = undef();
            }
        }
        if( !defined( $filename ) )
        {
            $filename = "auto/$sub.al";
            $filename =~ s/::/\//g;
        }
        my $save = $@;
        eval
        {
            local $SIG{ '__DIE__' }  = sub{ };
            local $SIG{ '__WARN__' } = sub{ };
            require $filename;
        };
        if( $@ )
        {
            if( substr( $sub, -9 ) eq '::DESTROY' )
            {
                *$sub = sub {};
            }
            else
            {
                # The load might just have failed because the filename was too
                # long for some old SVR3 systems which treat long names as errors.
                # If we can succesfully truncate a long name then it's worth a go.
                # There is a slight risk that we could pick up the wrong file here
                # but autosplit should have warned about that when splitting.
                if( $filename =~ s/(\w{12,})\.al$/substr( $1, 0, 11 ) . ".al"/e )
                {
                    eval
                    {
                        local $SIG{ '__DIE__' }  = sub{ };
                        local $SIG{ '__WARN__' } = sub{ };
                        require $filename
                    };
                }
                if( $@ )
                {
                    #$@ =~ s/ at .*\n//;
                    #my $error = $@;
                    #CORE::die( $error );
                    ## die( "Method $meth() is not defined in class $class and not autoloadable.\n" );
                    ## print( $err "EXTRA_AUTOLOAD is ", defined( &{ "${class}::EXTRA_AUTOLOAD" } ) ? "defined" : "not defined", " in package '$class'.\n" );
                    ## if( $self && defined( &{ "${class}::EXTRA_AUTOLOAD" } ) )
                    ## Look up in our caller's @ISA to see if there is any package that has this special
                    ## EXTRA_AUTOLOAD() sub routine
                    my $sub_ref = '';
                    die( "EXTRA_AUTOLOAD: ", join( "', '", @_ ), "\n" ) if( $func eq 'EXTRA_AUTOLOAD' );
                    if( $self && $func ne 'EXTRA_AUTOLOAD' && ( $sub_ref = $self->will( 'EXTRA_AUTOLOAD' ) ) )
                    {
                        ## return( &{ "${class}::EXTRA_AUTOLOAD" }( $self, $meth ) );
                        ## return( $self->EXTRA_AUTOLOAD( $AUTOLOAD, @_ ) );
                        return( $sub_ref->( $self, $AUTOLOAD, @_ ) );
                    }
                    else
                    {
						my $keys = CORE::join( ',', keys( %$hash ) );
						my $msg  = "Method $func() is not defined in class $class and not autoloadable in package $pkg in file $file at line $line.\n";
						$msg    .= "There are actually the following fields in the object '$self': '$keys'\n";
						die( $msg );
                    }
                }
            }
        }
        $@ = $save;
        if( $DEBUG )
        {
        	my $mesg = "unshifting '$self' to args for sub '$sub'.";
			if( $MOD_PERL )
			{
				my $r = Apache2::RequestUtil->request;
				$r->log_error( $mesg );
			}
			else
			{
				print( $err "$mesg\n" );
			}
        }
        unshift( @_, $self ) if( $self );
        #use overloading;
        goto &$sub;
        ## die( "Method $meth() is not defined in class $class and not autoloadable.\n" );
        ## my $mesg = "Method $meth() is not defined in class $class and not autoloadable.";
        ## $self->{ 'fatal' } ? die( $mesg ) : return( $self->error( $mesg ) );
    }
};

DESTROY
{
    ## Do nothing
};

package Module::Generic::Tie;
use Tie::Hash;
our( @ISA ) = qw( Tie::Hash );

sub TIEHASH
{
    my $self = shift( @_ );
    my $pkg  = ( caller() )[ 0 ];
    ## print( STDERR __PACKAGE__ . "::TIEHASH() called with following arguments: '", join( ', ', @_ ), "'.\n" );
    my %arg  = ( @_ );
    my $auth = [ $pkg, __PACKAGE__ ];
    if( $arg{ 'pkg' } )
    {
        my $ok = delete( $arg{ 'pkg' } );
        push( @$auth, ref( $ok ) eq 'ARRAY' ? @$ok : $ok );
    }
    my $priv = { 'pkg' => $auth };
    my $data = { '__priv__' => $priv };
    my @keys = keys( %arg );
    @$priv{ @keys } = @arg{ @keys };
    return( bless( $data, ref( $self ) || $self ) );
}

sub CLEAR
{
    my $self = shift( @_ );
    my $pkg = ( caller() )[ 0 ];
    ## print( $err __PACKAGE__ . "::CLEAR() called by package '$pkg'.\n" );
    my $data = $self->{ '__priv__' };
    return() if( $data->{ 'readonly' } && $pkg ne __PACKAGE__ );
    ## if( $data->{ 'readonly' } || $data->{ 'protect' } )
    if( !( $data->{ 'perms' } & 2 ) )
    {
        return() if( !grep( /^$pkg$/, @{ $data->{ 'pkg' } } ) );
    }
    my $key  = $self->FIRSTKEY( @_ );
    my @keys = ();
    while( defined( $key ) )
    {
        push( @keys, $key );
        $key = $self->NEXTKEY( @_, $key );
    }
    foreach $key ( @keys )
    {
        $self->DELETE( @_, $key );
    }
}

sub DELETE
{
    my $self = shift( @_ );
    my $pkg  = ( caller() )[ 0 ];
    $pkg     = ( caller( 1 ) )[ 0 ] if( $pkg eq 'Module::Generic' );
    ## print( STDERR __PACKAGE__ . "::DELETE() package '$pkg' tries to delete '$_[ 0 ]'\n" );
    my $data = $self->{ '__priv__' };
    return() if( $_[ 0 ] eq '__priv__' && $pkg ne __PACKAGE__ );
    ## if( $data->{ 'readonly' } || $data->{ 'protect' } )
    if( !( $data->{ 'perms' } & 2 ) )
    {
        return() if( !grep( /^$pkg$/, @{ $data->{ 'pkg' } } ) );
    }
    return( delete( $self->{ shift( @_ ) } ) );
}

sub EXISTS
{
    my $self = shift( @_ );
    ## print( STDERR __PACKAGE__ . "::EXISTS() called from package '", ( caller() )[ 0 ], "'.\n" );
    return( 0 ) if( $_[ 0 ] eq '__priv__' && $pkg ne __PACKAGE__ );
    my $data = $self->{ '__priv__' };
    if( !( $data->{ 'perms' } & 4 ) )
    {
        my $pkg = ( caller() )[ 0 ];
        return( 0 ) if( !grep( /^$pkg$/, @{$data->{ 'pkg' }} ) );
    }
    ## print( STDERR __PACKAGE__ . "::EXISTS() returns: '", exists( $self->{ $_[ 0 ] } ), "'.\n" );
    return( exists( $self->{ shift( @_ ) } ) );
}

sub FETCH
{
    ## return( shift->{ shift( @_ ) } );
    ## print( STDERR __PACKAGE__ . "::FETCH() called with arguments: '", join( ', ', @_ ), "'.\n" );
    my $self = shift( @_ );
    ## This is a hidden entry, we return nothing
    return() if( $_[ 0 ] eq '__priv__' && $pkg ne __PACKAGE__ );
    my $data = $self->{ '__priv__' };
    ## If we have to protect our object, we hide its inner content if our caller is not our creator
    ## if( $data->{ 'protect' } )
    if( !( $data->{ 'perms' } & 4 ) )
    {
        my $pkg = ( caller() )[ 0 ];
        ## print( STDERR __PACKAGE__ . "::FETCH() package '$pkg' wants to fetch the value of '$_[ 0 ]'\n" );
        return() if( !grep( /^$pkg$/, @{$data->{ 'pkg' }} ) );
    }
    return( $self->{ shift( @_ ) } );
}

sub FIRSTKEY
{
    my $self = shift( @_ );
    ## my $a    = scalar( keys( %$hash ) );
    ## return( each( %$hash ) );
    my $data = $self->{ '__priv__' };
    ## if( $data->{ 'protect' } )
    if( !( $data->{ 'perms' } & 4 ) )
    {
        my $pkg = ( caller( 0 ) )[ 0 ];
        ## print( STDERR __PACKAGE__ . "::FIRSTKEY() called by package '$pkg'\n" );
        return() if( !grep( /^$pkg$/, @{$data->{ 'pkg' }} ) );
    }
    ## print( STDERR __PACKAGE__ . "::FIRSTKEY(): gathering object's keys.\n" );
    my( @keys ) = grep( !/^__priv__$/, keys( %$self ) );
    $self->{ '__priv__' }->{ 'ITERATOR' } = \@keys;
    ## print( STDERR __PACKAGE__ . "::FIRSTKEY(): keys are: '", join( ', ', @keys ), "'.\n" );
    ## print( STDERR __PACKAGE__ . "::FIRSTKEY() returns '$keys[ 0 ]'.\n" );
    return( shift( @keys ) );
}

sub NEXTKEY
{
    my $self = shift( @_ );
    ## return( each( %$hash ) );
    my $data = $self->{ '__priv__' };
    ## if( $data->{ 'protect' } )
    if( !( $data->{ 'perms' } & 4 ) )
    {
        my $pkg = ( caller( 0 ) )[ 0 ];
        ## print( STDERR __PACKAGE__ . "::NEXTKEY() called by package '$pkg'\n" );
        return() if( !grep( /^$pkg$/, @{$data->{ 'pkg' }} ) );
    }
    my $keys = $self->{ '__priv__' }->{ 'ITERATOR' };
    ## print( STDERR __PACKAGE__ . "::NEXTKEY() returns '$_[ 0 ]'.\n" );
    return( shift( @$keys ) );
}

sub STORE
{
    my $self = shift( @_ );
    return() if( $_[ 0 ] eq '__priv__' );
    my $data = $self->{ '__priv__' };
    #if( $data->{ 'readonly' } || 
    #    $data->{ 'protect' } )
    if( !( $data->{ 'perms' } & 2 ) )
    {
        my $pkg  = ( caller() )[ 0 ];
        $pkg     = ( caller( 1 ) )[ 0 ] if( $pkg eq 'Module::Generic' );
        ## print( STDERR __PACKAGE__ . "::STORE() package '$pkg' is trying to STORE the value '$_[ 1 ]' to key '$_[ 0 ]'\n" );
        return() if( !grep( /^$pkg$/, @{ $data->{ 'pkg' } } ) );
    }
    ## print( STDERR __PACKAGE__ . "::STORE() ", ( caller() )[ 0 ], " is storing value '$_[ 1 ]' for key '$_[ 0 ]'.\n" );
    ## $self->{ shift( @_ ) } = shift( @_ );
    $self->{ $_[ 0 ] } = $_[ 1 ];
    ## print( STDERR __PACKAGE__ . "::STORE(): object '$self' now contains: '", join( ', ', map{ "$_, $self->{ $_ }" } keys( %$self ) ), "'.\n" );
}

1;

__END__

=head1 NAME

Module::Generic - Generic Module to inherit from

=head1 SYNOPSIS

    package MyModule;
    BEGIN
    {
        use strict;
        use Module::Generic;
        our( @ISA ) = qw( Module::Generic );
    };

=head1 DESCRIPTION

C<Module::Generic> as its name says it all, is a generic module to inherit from.
It contains standard methods that may howerver be bypassed by the module using 
C<Module::Generic>.

As an added benefit, it also contains a powerfull AUTOLOAD transforming any hash 
object key into dynamic methods and also recognize the dynamic routine a la AutoLoader
from which I have shamelessly copied in the AUTOLOAD code. The reason is that while
C<AutoLoader> provides the user with a convenient AUTOLOAD, I wanted a way to also
keep the functionnality of C<Module::Generic> AUTOLOAD that were not included in
C<AutoLoader>. So the only solution was a merger.

=head1 METHODS

=over 4

=item B<import>()

B<import>() is used for the AutoLoader mechanism and hence is not a public method.
It is just mentionned here for info only.

=item B<new>()

B<new>() will create a new object for the package, pass any argument it might receive
to the special standard routine B<init> that I<must> exist. 
Then it returns what returns B<init>().

To protect object inner content from sneaking by thrid party, you can declare the 
package global variable I<OBJECT_PERMS> and give it a Unix permission.
It will then work just like Unix permission. That is, if permission is 700, then only the 
module who generated the object may read/write content of the object. However, if
you set 755, the, other may look into the content of the object, but may not modify it.
777, as you would have guessed, allow other to modify the content of an object.
If I<OBJECT_PERMS> is not defined, permissions system is not activated and hence anyone 
may access and possibibly modify the content of your object.

If the module runs under mod_perl, it is recognized and a clean up registered routine is 
declared to Apache to clean up the content of the object.

=item B<clear_error>

Clear all error from the object and from the available global variable C<$ERROR>.

This is a handy method to use at the beginning of other methods of calling package,
so the end user may do a test such as:

    $obj->some_method( 'some arguments' );
    die( $obj->error() ) if( $obj->error() );

    ## some_method() would then contain something like:
    sub some_method
    {
        my $self = shift( @_ );
        ## Clear all previous error, so we may set our own later one eventually
        $self->clear_error();
        ## ...
    }

This way the end user may be sure that if C<$obj->error()> returns true something
wrong has occured.

=item B<error>()

Set the current error, do a warn on it and returns undef():

    if( $some_condition )
    {
        return( $self->error( "Some error." ) );
    }

Note that you do not have to worry about a trailing line feed sequence.
B<error>() takes care of it.

Note also that by calling B<error>() it will not clear the current error. For that
you have to call B<clear_error>() explicitly.

Also, when an error is set, the global variable I<ERROR> is set accordingly. This is
especially usefull, when your initiating an object and that an error occured. At that
time, since the object could not be initiated, the end user can not use the object to 
get the error message, and then can get it using the global module variable 
I<ERROR>, for example:

    my $obj = Some::Package->new ||
    die( $Some::Package::ERROR, "\n" );

=item B<errors>()

Used by B<error>() to store the error sent to him for history.

It returns an array of all error that have occured in lsit context, and the last 
error in scalar context.

=item B<errstr>()

Set/get the error string, period. It does not produce any warning like B<error> would do.

=item B<get>()

Uset to get an object data key value:

    $obj->set( 'verbose' => 1, 'debug' => 0 );
    ## ...
    my $verbose = $obj->get( 'verbose' );
    my @vals = $obj->get( qw( verbose debug ) );
    print( $out "Verbose level is $vals[ 0 ] and debug level is $vals[ 1 ]\n" );

This is no more needed, as it has been more conveniently bypassed by the AUTOLOAD
generic routine with chich you may say:

    $obj->verbose( 1 );
    $obj->debug( 0 );
    ## ...
    my $verbose = $obj->verbose();

Much better, no?

=item B<init>()

This is the B<new>() package object initializer. It is called by B<new>()
and is used to set up any parameter provided in a hash like fashion:

    my $obj My::Module->new( 'verbose' => 1, 'debug' => 0 );

You may want to superseed B<init>() to have suit your needs.

B<init>() needs to returns the object it received in the first place or an error if
something went wrong, such as:

    sub init
    {
        my $self = shift( @_ );
        my $dbh  = DB::Object->connect() ||
        return( $self->error( "Unable to connect to database server." ) );
        $self->{ 'dbh' } = $dbh;
        return( $self );
    }

In this example, using B<error> will set the global variable C<$ERROR> that will
contain the error, so user can say:

    my $obj = My::Module->new() || die( $My::Module::ERROR );

If the global variable I<VERBOSE>, I<DEBUG>, I<VERSION> are defined in the module,
and that they do not exist as an object key, they will be set automatically and
accordingly to those global variable.

The supported data type of the object generated by the B<new> method may either be
a hash reference or a glob reference. Those supported data types may very well be
extended to an array reference in a near future.

=item B<message>()

B<message>() is used to display verbose/debug output. It will display something
to the extend that either I<verbose> or I<debug> are toggled on.

If so, all debugging message will be prepended by C<## > to highlight the fact
that this is a debugging message.

Addionally, if a number is provided as first argument to B<message>(), it will be 
treated as the minimum required level of debugness. So, if the current debug
state level is not equal or superior to the one provided as first argument, the
message will not be displayed.

For example:

    ## Set debugness to 3
    $obj->debug( 3 );
    ## This message will not be printed
    $obj->message( 4, "Some detailed debugging stuff that we might not want." );
    ## This will be displayed
    $obj->message( 2, "Some more common message we want the user to see." );

Now, why debug is used and not verbose level? Well, because mostly, the verbose level
needs only to be true, that is equal to 1 to be efficient. You do not really need to have
a verbose level greater than 1. However, the debug level usually may have various level.

=item B<set>()

B<set>() sets object inner data type and takes arguments in a hash like fashion:

    $obj->set( 'verbose' => 1, 'debug' => 0 );

=item B<subclasses>( [ CLASS ] )

This method try to guess all the existing sub classes of the provided I<CLASS>.

If I<CLASS> is not provided, the class into which was blessed the calling object will
be used instead.

It returns an array of subclasses in list context and a reference to an array of those
subclasses in scalar context.

If an error occured, undef is returned and an error is set accordingly. The latter can
be retrieved using the B<error> method.

=item B<AUTOLOAD>

The special B<AUTOLOAD>() routine is called by perl when no mathing routine was found
in the module.

B<AUTOLOAD>() will then try hard to process the request.
For example, let's assue we have a routine B<foo>.

It will first, check if an equivalent entry of the routine name that was called exist in
the hash reference of the object. If there is and that more than one argument were
passed to this non existing routine, those arguments will be stored as a reference to an
array as a value of the key in the object. Otherwise the single argument will simply be stored
as the value of the key of the object.

Then, if called in list context, it will return a array if the value of the key entry was an array
reference, or a hash list if the value of the key entry was a hash reference, or finally the value
of the key entry.

If this non existing routine that was called is actually defined, the routine will be redeclared and
the arguments passed to it.

If this fails too, it will try to check for an AutoLoadable file in C<auto/PackageName/routine_name.al>

If the filed exists, it will be required, the routine name linked into the package name space and finally
called with the arguments.

If the require process failed or if the AutoLoadable routine file did not exist, B<AUTOLOAD>() will
check if the special routine B<EXTRA_AUTOLOAD>() exists in the module. If it does, it will call it and pass
it the arguments. Otherwise, B<AUTOLOAD> will die with a message explaining that the called routine did 
not exist and could not be found in the current class.

=back

=head1 COPYRIGHT

Copyright (c) 2000-2014 DEGUEST Pte. Ltd.

=head1 CREDITS

Jacques Deguest E<lt>F<jack@deguest.jp>E<gt>

=head1 SEE ALSO

=cut
