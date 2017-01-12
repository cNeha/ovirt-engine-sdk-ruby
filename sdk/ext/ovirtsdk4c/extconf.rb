#!/usr/bin/ruby

#
# Copyright (c) 2015-2016 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'mkmf'

# Check that "libxml2" is available:
unless find_executable('xml2-config')
  raise 'The "libxml2" package isn\'t available.'
end
$CPPFLAGS = "#{`xml2-config --cflags`.strip} #{$CPPFLAGS}"
$LDFLAGS = "#{`xml2-config --libs`.strip} #{$LDFLAGS}"

# Check that "libcurl" is available:
unless pkg_config('libcurl')
  raise 'The "libcurl" package isn\'t available.'
end

# When installing the SDK as a plugin in Vagrant there is an issue with
# some versions of Vagrant that embed "libxml2" and "libcurl", but using
# an incorrect directory. To avoid that we need to explicitly fix the
# Vagrant path.
def fix_vagrant_prefix(flags)
  flags.gsub!('/vagrant-substrate/staging', '/opt/vagrant')
end
fix_vagrant_prefix($CPPFLAGS)
fix_vagrant_prefix($LDFLAGS)

# Create the Makefile:
create_makefile 'ovirtsdk4c'
