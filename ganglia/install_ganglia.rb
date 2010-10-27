#!/usr/bin/ruby

# by: Jason Amster <jamster@beenverified.com
# Copyright BeenVerified.com Inc 2010
# 2010-10-25
# 
# Installs Ganglia on EMR cluster.  Should be run with the run-if bootstrap
# action so that it installs the right software on the name-node vs slave-nodes
# 
# --bootstrap-action s3://bfd-emr-apps/bootstraps/run_if --args "instance.isMaster=true,s3://bfd-emr-apps/bootstraps/install_ganglia.rb,master" \
# --bootstrap-action s3://bfd-emr-apps/bootstraps/run_if --args "instance.isMaster!=true,s3://bfd-emr-apps/bootstraps/install_ganglia.rb,slave" \

# Reference Articles that got me here.
#  - https://docs.google.com/Doc?id=dgmmft5s_45hr7hmggr
#  - http://www.manamplified.org/archives/2008/03/notes-on-using-ec2-s3.html

require 'fileutils'
require 'open-uri'
require '/usr/lib64/ruby/1.8/json'


# Get the info files for EMR so we can determine if we are in a master node
# or if we are slave node
INFO_DIR = "/mnt/var/lib/info/"
MASTER_NODE = JSON.parse(File.read(INFO_DIR + "job-flow.json"))['masterPrivateDnsName']

# Set up the ganglia source files
GANGLIA = "ganglia-3.1.7"
GANGLIA_HOME = "~/source/#{GANGLIA}"


# Get args for master/slave
unless ARGV[0]
  puts "You need to specify node type 'master' or 'slave'"  
  exit
end

if ARGV[0] == "master"
  SLAVE = false
else
  SLAVE = true
end

def log(string)
  puts Time.new.strftime("%Y-%m-%d %H:%M:%S") + " " + string
  STDOUT.flush  
end

def run_command(command, verbose = true)
  log("Running command: '#{command}'") if verbose
  results = `#{command} 2>&1`
  failure = $?
  log("Command output: " + results) if verbose
  if failure != 0 then
    raise "Got failure status #{failure} running #{command}"
  end
  return results
end

def run_commands(commands)
  commands.each_line do |command|
    run_command command.strip
  end
end

def download_and_unzip_ganglia
  run_command "(mkdir -p ~/source)"
  run_command "(cd ~/source && wget https://bfd-cluster-apps.s3.amazonaws.com/#{GANGLIA}.tar)"
  run_command "(cd ~/source && tar xvf #{GANGLIA}.tar)"
end

def update_hadoop_metrics
  hadoop_config = DATA.read.gsub(/@GANGLIA@/, MASTER_NODE)
  run_command "sudo mv /home/hadoop/conf/hadoop-metrics.properties /home/hadoop/conf/hadoop-metrics.properties.bak"
  file = File.open('/home/hadoop/conf/hadoop-metrics.properties', 'w')
  file.puts hadoop_config
  file.close
end

def install_php
php = <<-PHPCONF
  # PHP Configuration for Apache
  #
  # Load the apache module
  #
  LoadModule php5_module modules/libphp5.so
  #
  # Cause the PHP interpreter handle files with a .php extension.
  #
  <Files *.php>
  SetOutputFilter PHP
  SetInputFilter PHP
  LimitRequestBody 9524288
  </Files>
  AddType application/x-httpd-php .php
  AddType application/x-httpd-php-source .phps
  #
  # Add index.php to the list of files that will be served as directory
  # indexes.
  #
  DirectoryIndex index.php
PHPCONF
  run_command "touch /home/hadoop/php.conf"
  file = File.open('/home/hadoop/php.conf', 'w')
  file.puts php
  file.close
  run_command "sudo mv /home/hadoop/php.conf /etc/apache2/conf.d/php.conf"
  run_command "sudo /etc/init.d/apache2 stop"
  run_command "sudo /etc/init.d/apache2 start"
end

def install_web_frontend
  run_commands  <<-COMMANDS 
  sudo apt-get install rrdtool -y
  sudo apt-get install apache2 php5-mysql libapache2-mod-php5 php-pear -y
  sudo cp -r #{GANGLIA_HOME}/web /var/www && sudo mv /var/www/web /var/www/ganglia
  COMMANDS
  install_php
  # run_command 'sudo /etc/init.d/apache2 restart'
end

# Need to do a bunch of modifications here b/c EMR/EC2 doesn't support 
# multicast
def configure_gmond
  run_commands <<-COMMANDS
  sudo gmond --default_config > ~/gmond.conf
  sudo mv ~/gmond.conf /etc/ganglia/gmond.conf
  sudo perl -pi -e 's/name = "unspecified"/name = "bfd"/g' /etc/ganglia/gmond.conf
  sudo perl -pi -e 's/owner = "unspecified"/name = "bfd"/g' /etc/ganglia/gmond.conf
  sudo perl -pi -e 's/send_metadata_interval = 0/send_metadata_interval = 5/g' /etc/ganglia/gmond.conf
  export MASTER_HOST=#{MASTER_NODE}
  COMMANDS
  
  if !SLAVE
    command = <<-COMMAND
    sudo sed -i -e "s|\\( *mcast_join *=.*\\)|#\\1|" \
           -e "s|\\( *bind *=.*\\)|#\\1|" \
           -e "s|\\( *location *=.*\\)|  location = \"master-node\"|" \
           -e "s|\\(udp_send_channel {\\)|\\1\\n  host=#{MASTER_NODE}|" \
           /etc/ganglia/gmond.conf
    COMMAND
    run_command(command)
  else
    command = <<-COMMAND
    sudo sed -i -e "s|\\( *mcast_join *=.*\\)|#\\1|"  \
           -e "s|\\( *bind *=.*\\)|#\\1|" \
           -e "s|\\(udp_send_channel {\\)|\\1\\n  host=#{MASTER_NODE}|" \
           /etc/ganglia/gmond.conf
    COMMAND
    run_command(command)
  end
  run_command("sudo gmond")
end

# Directories here are overkill i'm sure, but too frustrated to play with them
def configure_gmetad
  rrds_home = "/mnt/var/lib/ganglia/rrds"
  rrds_link = "/var/lib/ganglia/rrds"
  run_commands <<-COMMANDS
  sudo cp #{GANGLIA_HOME}/gmetad/gmetad.conf /etc/ganglia/
  sudo mkdir -p #{rrds_home}
  sudo mkdir -p /var/lib/ganglia
  sudo chown -R nobody #{rrds_home}
  sudo chown -R nobody /var/lib/ganglia
  sudo ln -nfs #{rrds_home} #{rrds_link}
  sudo chown -R nobody #{rrds_link}
  sudo gmetad 
  COMMANDS
end

update_hadoop_metrics

if SLAVE # SLAVE
  run_command "(sudo apt-get install build-essential libapr1-dev libconfuse-dev libexpat1-dev python-dev -y)"
  download_and_unzip_ganglia
  run_command "(cd #{GANGLIA_HOME} && ./configure --sysconfdir=/etc/ganglia)"
  run_command "(cd #{GANGLIA_HOME} && make)"
  run_command "(cd #{GANGLIA_HOME} && sudo make install)"
  configure_gmond
else # MASTER
  run_command "(sudo apt-get install build-essential librrd-dev libapr1-dev libconfuse-dev libexpat1-dev python-dev -y)"
  download_and_unzip_ganglia
  run_command "(cd #{GANGLIA_HOME} && ./configure --with-gmetad --sysconfdir=/etc/ganglia && make && sudo make install)"
  configure_gmond
  configure_gmetad
  install_web_frontend
end

exit(0)

__END__
dfs.class=org.apache.hadoop.metrics.ganglia.GangliaContext
dfs.period=10
dfs.servers=@GANGLIA@:8649

mapred.class=org.apache.hadoop.metrics.ganglia.GangliaContext
mapred.period=10
mapred.servers=@GANGLIA@:8649

jvm.class=org.apache.hadoop.metrics.ganglia.GangliaContext
jvm.period=10
jvm.servers=@GANGLIA@:8649

rpc.class=org.apache.hadoop.metrics.ganglia.GangliaContext
rpc.period=10
rpc.servers=@GANGLIA@:8649
