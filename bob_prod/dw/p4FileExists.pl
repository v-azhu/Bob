
( @files ) = @ARGV;

foreach $file ( sort @files ) {
   $command = "p4 files $file";

   open ( FILE, "$command 2>&1 |" ) or die "Couldn't run command:  $command\n";
   {
      local( $/ );
      $output = <FILE>;
   }
   close ( FILE );

   die "File doesn't exist in perforce:  $file\n" if ( $output =~ /(?:no such file| - delete)/ );
}

exit ( 0 );

