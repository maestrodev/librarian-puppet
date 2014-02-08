# Librarian-puppet

[![Build Status](https://travis-ci.org/maestrodev/librarian-puppet.png?branch=maestrodev)](https://travis-ci.org/maestrodev/librarian-puppet)

## Note

**Since 0.9.11.6 this fork is no longer used, as I am committing directly to [rodjek's librarian-puppet](https://github.com/rodjek/librarian-puppet) and pushing to [librarian-puppet](https://rubygems.org/gems/librarian-puppet)**

**librarian-puppet-maestrodev 0.9.11.6 is effectively the same as librarian-puppet 0.9.11**

## Introduction

Librarian-puppet is a bundler for your puppet infrastructure.  You can use
librarian-puppet to manage the puppet modules your infrastructure depends on.
It is based on [Librarian](https://github.com/applicationsonline/librarian), a
framework for writing bundlers, which are tools that resolve, fetch, install,
and isolate a project's dependencies.

Librarian-puppet manages your `modules/` directory for you based on your
`Puppetfile`.  Your `Puppetfile` becomes the authoritative source for what
modules you require and at what version, tag or branch.

Once using Librarian-puppet you should not modify the contents of your `modules`
directory.  The individual modules' repos should be updated, tagged with a new
release and the version bumped in your Puppetfile.

## The Puppetfile

Every Puppet repository that uses Librarian-puppet will have a file named
`Puppetfile` in the root directory of that repository.  The full specification
for which modules your puppet infrastructure repository  depends goes in here.

### Simple Puppetfile

This Puppetfile will download all the dependencies listed in your Modulefile from the Puppet Forge

    forge "http://forge.puppetlabs.com"

    modulefile


### Example Puppetfile

    forge "http://forge.puppetlabs.com"

    mod "puppetlabs/razor"
    mod "puppetlabs/ntp", "0.0.3"

    mod "apt",
      :git => "git://github.com/puppetlabs/puppetlabs-apt.git"

    mod "stdlib",
      :git => "git://github.com/puppetlabs/puppetlabs-stdlib.git"

*See [jenkins-appliance](https://github.com/aussielunix/jenkins-appliance) for
a puppet repo already setup to use librarian-puppet.*

### Recursive module dependency resolving

When fetching a module from a `:git`-source all dependencies specified in its
`Modulefile` and `Puppetfile` will be resolved and installed.

### Puppetfile Breakdown

    forge "http://forge.puppetlabs.com"

This declares that we want to use the official Puppet Labs Forge as our default
source when pulling down modules.  If you run your own local forge, you may
want to change this.

    mod "puppetlabs/razor"

Pull in the latest version of the Puppet Labs Razor module from the default
source.

    mod "puppetlabs/ntp", "0.0.3"

Pull in version 0.0.3 of the Puppet Labs NTP module from the default source.

    mod "apt",
      :git => "git://github.com/puppetlabs/puppetlabs-apt.git"

Our puppet infrastructure repository depends on the `apt` module from the
Puppet Labs GitHub repos and checks out the `master` branch.

    mod "apt",
      :git => "git://github.com/puppetlabs/puppetlabs-apt.git",
      :ref => '0.0.3'

Our puppet infrastructure repository depends on the `apt` module from the
Puppet Labs GitHub repos and checks out a tag of `0.0.3`.

    mod "apt",
      :git => "git://github.com/puppetlabs/puppetlabs-apt.git",
      :ref => 'feature/master/dans_refactor'

Our puppet infrastructure repository depends on the `apt` module from the
Puppet Labs GitHub repos and checks out the `dans_refactor` branch.

When using a Git source, we do not have to use a `:ref =>`.
If we do not, then librarian-puppet will assume we meant the `master` branch.

If we use a `:ref =>`, we can use anything that Git will recognize as a ref.
This includes any branch name, tag name, SHA, or SHA unique prefix. If we use a
branch, we can later ask Librarian-puppet to update the module by fetching the
most recent version of the module from that same branch.

The Git source also supports a `:path =>` option. If we use the path option,
Librarian-puppet will navigate down into the Git repository and only use the
specified subdirectory. Some people have the habit of having a single repository
with many modules in it. If we need a module from such a repository, we can
use the `:path =>` option here to help Librarian-puppet drill down and find the
module subdirectory.

    mod "apt",
      :git => "git://github.com/fake/puppet-modules.git",
      :path => "modules/apt"

Our puppet infrastructure repository depends on the `apt` module, which we have
stored as a directory under our `puppet-modules` git repos.

## How to Use

Install librarian-puppet:

    $ gem install librarian-puppet

Prepare your puppet infrastructure repository:

    $ cd ~/path/to/puppet-inf-repos
    $ (git) rm -rf modules
    $ librarian-puppet init

Librarian-puppet takes over your `modules/` directory, and will always
reinstall (if missing) the modules listed the `Puppetfile.lock` into your
`modules/` directory, therefore you do not need your `modules/` directory to be
tracked in Git.

Librarian-puppet uses a `.tmp/` directory for tempfiles and caches. You should
not track this directory in Git.

Running `librarian-puppet init` will create a skeleton Puppetfile for you as
well as adding `tmp/` and `modules/` to your `.gitignore`.

    $ librarian-puppet install [--clean] [--verbose]

This command looks at each `mod` declaration and fetches the module from the
source specified.  This command writes the complete resolution into
`Puppetfile.lock` and then copies all of the fetched modules into your
`modules/` directory, overwriting whatever was there before.

Get an overview of your `Puppetfile.lock` with:

    $ librarian-puppet show

Inspect the details of specific resolved dependencies with:

    $ librarian-puppet show NAME1 [NAME2, ...]

Find out which dependencies are outdated and may be updated:

    $ librarian-puppet outdated [--verbose]

Update the version of a dependency:

    $ librarian-puppet update apt [--verbose]
    $ git diff Puppetfile.lock
    $ git add Puppetfile.lock
    $ git commit -m "bumped the version of apt up to 0.0.4."

## Configuration

Configuration comes from three sources with the following highest-to-lowest
precedence:

* The local config (`./.librarian/puppet/config`)
* The environment
* The global config (`~/.librarian/puppet/config`)

You can inspect the final configuration with:

    $ librarian-puppet config

You can find out where a particular key is set with:

    $ librarian-puppet config KEY

You can set a key at the global level with:

    $ librarian-puppet config KEY VALUE --global

And remove it with:

    $ librarian-puppet config KEY --global --delete

You can set a key at the local level with:

    $ librarian-puppet config KEY VALUE --local

And remove it with:

    $ librarian-puppet config KEY --local --delete

You cannot set or delete environment-level config keys with the CLI.

Configuration set at either the global or local level will affect subsequent
invocations of `librarian-puppet`. Configurations set at the environment level are
not saved and will not affect subsequent invocations of `librarian-puppet`.

You can pass a config at the environment level by taking the original config key
and transforming it: replace hyphens (`-`) with underscores (`_`) and periods
(`.`) with doubled underscores (`__`), uppercase, and finally prefix with
`LIBRARIAN_PUPPET_`. For example, to pass a config in the environment for the key
`part-one.part-two`, set the environment variable
`LIBRARIAN_PUPPET_PART_ONE__PART_TWO`.

Configuration affects how various commands operate.

* The `path` config sets the cookbooks directory to install to. If a relative
  path, it is relative to the directory containing the `Puppetfile`. The
  equivalent environment variable is `LIBRARIAN_PUPPET_PATH`.

* The `tmp` config sets the cache directory for librarian. If a relative
  path, it is relative to the directory containing the `Puppetfile`. The
  equivalent environment variable is `LIBRARIAN_PUPPET_TMP`.

Configuration can be set by passing specific options to other commands.

* The `path` config can be set at the local level by passing the `--path` option
  to the `install` command. It can be unset at the local level by passing the
  `--no-path` option to the `install` command. Note that if this is set at the
  environment or global level then, even if `--no-path` is given as an option,
  the environment or global config will be used.



## How to Contribute

 * Pull requests please.
 * Bonus points for feature branches.

## Reporting Issues

Bug reports to the github issue tracker please.
Please include:

 * Relevant `Puppetfile` and `Puppetfile.lock` files
 * Version of ruby, librarian-puppet
 * What distro
 * Please run the `librarian-puppet` commands in verbose mode by using the
  `--verbose` flag, and include the verbose output in the bug report as well.


## License
Please see the [LICENSE](https://github.com/rodjek/librarian-puppet/blob/master/LICENSE)
file.
