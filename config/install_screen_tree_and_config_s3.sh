#!/bin/bash

sudo apt-get install screen tree

cat <<-OUTPUT > /home/hadoop/.s3cfg
[default]
access_key = [REPLACE_THIS_WITH_YOUR_ACCESS_KEY]
acl_public = False
bucket_location = US
debug_syncmatch = False
default_mime_type = binary/octet-stream
delete_removed = False
dry_run = False
encrypt = False
force = False
gpg_command = /usr/local/bin/gpg
gpg_decrypt = %(gpg_command)s -d --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_encrypt = %(gpg_command)s -c --verbose --no-use-agent --batch --yes --passphrase-fd %(passphrase_fd)s -o %(output_file)s %(input_file)s
gpg_passphrase = [REPLACE_THIS_WITH_YOUR_PASSWORD]
guess_mime_type = False
host_base = s3.amazonaws.com
host_bucket = %(bucket)s.s3.amazonaws.com
human_readable_sizes = False
preserve_attrs = True
proxy_host =
proxy_port = 0
recv_chunk = 4096
secret_key = [REPLACE_THIS_WITH_YOUR_SECRET_KEY]
send_chunk = 4096
simpledb_host = sdb.amazonaws.com
use_https = True
verbosity = WARNING
OUTPUT


