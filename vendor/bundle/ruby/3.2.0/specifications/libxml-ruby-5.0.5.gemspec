# -*- encoding: utf-8 -*-
# stub: libxml-ruby 5.0.5 ruby lib
# stub: ext/libxml/extconf.rb

Gem::Specification.new do |s|
  s.name = "libxml-ruby".freeze
  s.version = "5.0.5"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "documentation_uri" => "https://xml4r.github.io/libxml-ruby/" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Ross Bamform".freeze, "Wai-Sun Chia".freeze, "Sean Chittenden".freeze, "Dan Janwoski".freeze, "Anurag Priyam".freeze, "Charlie Savage".freeze, "Ryan Johnson".freeze]
  s.date = "2025-07-30"
  s.description = "    The Libxml-Ruby project provides Ruby language bindings for the GNOME\n    Libxml2 XML toolkit. It is free software, released under the MIT License.\n    Libxml-ruby's primary advantage over REXML is performance - if speed\n    is your need, these are good libraries to consider, as demonstrated\n    by the informal benchmark below.\n".freeze
  s.extensions = ["ext/libxml/extconf.rb".freeze]
  s.files = ["ext/libxml/extconf.rb".freeze]
  s.homepage = "https://xml4r.github.io/libxml-ruby/".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Ruby Bindings for LibXML2".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_development_dependency(%q<logger>.freeze, [">= 0"])
  s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0"])
  s.add_development_dependency(%q<minitest>.freeze, [">= 0"])
end
