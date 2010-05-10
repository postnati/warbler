#--
# Copyright (c) 2010 Engine Yard, Inc.
# Copyright (c) 2007-2009 Sun Microsystems, Inc.
# This source code is available under the MIT license.
# See the file LICENSE.txt for details.
#++

require 'ostruct'

module Warbler
  # Warbler war file assembly configuration class.
  class Config
    TOP_DIRS = %w(app config lib log vendor)
    FILE = "config/warble.rb"
    DEFAULT_GEM_PATH = '/WEB-INF/gems'
    BUILD_GEMS = %w(warbler rake rcov)

    # Features: additional options controlling how the jar is built.
    # Currently the following features are supported:
    # - gemjar: package the gem repository in a jar file in WEB-INF/lib
    attr_accessor :features

    # Deprecated: No longer has any effect.
    attr_accessor :staging_dir

    # A hash of files that Warbler will build into the .war file. Keys
    # to the hash are filenames in the .war, values are either nil
    # (for a directory entry), the source filenames or IO objects for
    # temporary file contents. This will be filled with files by the
    # various Warbler tasks as they run. You can add arbitrary
    # filenames to this hash if you wish.
    attr_accessor :files

    # Directory where the war file will be written. Can be used to direct
    # Warbler to place your war file directly in your application server's
    # autodeploy directory. Defaults to the root of the Rails directory.
    attr_accessor :autodeploy_dir

    # Top-level directories to be copied into WEB-INF.  Defaults to
    # names in TOP_DIRS
    attr_accessor :dirs

    # Additional files beyond the top-level directories to include in the
    # WEB-INF directory
    attr_accessor :includes

    # Files to exclude from the WEB-INF directory
    attr_accessor :excludes

    # Java classes and other files to copy to WEB-INF/classes
    attr_accessor :java_classes

    # Java libraries to copy to WEB-INF/lib
    attr_accessor :java_libs

    # Rubygems to install into the webapp.
    attr_accessor :gems

    # Whether to include dependent gems (default true)
    attr_accessor :gem_dependencies

    # Whether to exclude **/*.log files (default is true)
    attr_accessor :exclude_logs

    # Public HTML directory file list, to be copied into the root of the war
    attr_accessor :public_html

    # Container of pathmaps used for specifying source-to-destination transformations
    # under various situations (<tt>public_html</tt> and <tt>java_classes</tt> are two
    # entries in this structure).
    attr_accessor :pathmaps

    # Name of war file (without the .war), defaults to the directory name containing
    # the Rails application
    attr_accessor :war_name

    # Name of a MANIFEST.MF template to use.
    attr_accessor :manifest_file

    # Files for WEB-INF directory (next to web.xml). Contains web.xml by default.
    # If there are .erb files they will be processed with webxml config.
    attr_accessor :webinf_files

    # Use Bundler to locate gems if Gemfile is found. Default is true.
    attr_accessor :bundler

    # Path to the pre-bundled gem directory inside the war file. Default is '/WEB-INF/gems'.
    # This also sets 'gem.path' inside web.xml.
    attr_accessor :gem_path

    # Extra configuration for web.xml. Controls how the dynamically-generated web.xml
    # file is generated.
    #
    # * <tt>webxml.jndi</tt> -- the name of one or more JNDI data sources name to be
    #   available to the application. Places appropriate &lt;resource-ref&gt; entries
    #   in the file.
    # * <tt>webxml.ignored</tt> -- array of key names that will be not used to
    #   generate a context param. Defaults to ['jndi', 'booter']
    #
    # Any other key/value pair placed in the open structure will be dumped as a
    # context parameter in the web.xml file. Some of the recognized values are:
    #
    # * <tt>webxml.rails.env</tt> -- the Rails environment to use for the
    #   running application, usually either development or production (the
    #   default).
    # * <tt>webxml.gem.path</tt> -- the path to your bundled gem directory
    # * <tt>webxml.jruby.min.runtimes</tt> -- minimum number of pooled runtimes to
    #   keep around during idle time
    # * <tt>webxml.jruby.max.runtimes</tt> -- maximum number of pooled Rails
    #   application runtimes
    #
    # Note that if you attempt to access webxml configuration keys in a conditional,
    # you might not obtain the result you want. For example:
    #     <%= webxml.maybe.present.key || 'default' %>
    # doesn't yield the right result. Instead, you need to generate the context parameters:
    #     <%= webxml.context_params['maybe.present.key'] || 'default' %>
    attr_accessor :webxml

    def initialize(warbler_home = WARBLER_HOME)
      @warbler_home = warbler_home
      @features    = []
      @dirs        = TOP_DIRS.select {|d| File.directory?(d)}
      @includes    = FileList[]
      @excludes    = FileList[]
      @java_libs   = default_jar_files
      @java_classes = FileList[]
      @gems        = Warbler::Gems.new
      @gem_path    = DEFAULT_GEM_PATH
      @gem_dependencies = true
      @exclude_logs = true
      @public_html = FileList["public/**/*"]
      @pathmaps    = default_pathmaps
      @webxml      = default_webxml_config
      @rails_root  = File.expand_path(defined?(RAILS_ROOT) ? RAILS_ROOT : Dir.getwd)
      @war_name    = File.basename(@rails_root)
      @bundler     = true
      @webinf_files = default_webinf_files
      auto_detect_frameworks
      yield self if block_given?
      update_gem_path
      detect_bundler_gems
      @excludes += warbler_vendor_excludes(warbler_home)
      @excludes += FileList["**/*.log"] if @exclude_logs
    end

    def gems=(value)
      @gems = Warbler::Gems.new(value)
    end

    def relative_gem_path
      @gem_path[1..-1]
    end

    private
    def warbler_vendor_excludes(warbler_home)
      warbler = File.expand_path(warbler_home)
      if warbler =~ %r{^#{@rails_root}/(.*)}
        FileList["#{$1}"]
      else
        []
      end
    end

    def default_pathmaps
      p = OpenStruct.new
      p.public_html  = ["%{public/,}p"]
      p.java_libs    = ["WEB-INF/lib/%f"]
      p.java_classes = ["WEB-INF/classes/%p"]
      p.application  = ["WEB-INF/%p"]
      p.webinf       = ["WEB-INF/%{.erb$,}f"]
      p.gemspecs     = ["#{relative_gem_path}/specifications/%f"]
      p.gems         = ["#{relative_gem_path}/gems/%p"]
      p
    end

    def default_webxml_config
      c = WebxmlOpenStruct.new
      c.rails.env  = ENV['RAILS_ENV'] || 'production'
      c.public.root = '/'
      c.jndi = nil
      c.ignored = %w(jndi booter)
      c
    end

    def default_webinf_files
      webxml = if File.exist?("config/web.xml")
        "config/web.xml"
      elsif File.exist?("config/web.xml.erb")
        "config/web.xml.erb"
      else
        "#{WARBLER_HOME}/web.xml.erb"
      end
      FileList[webxml]
    end

    def update_gem_path
      if @gem_path != DEFAULT_GEM_PATH
        @gem_path = "/#{@gem_path}" unless @gem_path =~ %r{^/}
        sub_gem_path = @gem_path[1..-1]
        @pathmaps.gemspecs.each {|p| p.sub!(DEFAULT_GEM_PATH[1..-1], sub_gem_path)}
        @pathmaps.gems.each {|p| p.sub!(DEFAULT_GEM_PATH[1..-1], sub_gem_path)}
        @webxml["gem"]["path"] = @gem_path
      end
    end

    def detect_bundler_gems
      if @bundler && File.exist?("Gemfile")
        @gems.clear
        @gem_dependencies = false # Bundler takes care of these
        begin
          require 'bundler'
          env = Bundler::Runtime.new(Bundler.root, Bundler.definition)
          if bundler_env_file = Bundler.respond_to?(:env_file)
            class << Bundler
              alias orig_env_file env_file
              def env_file; root.join(::Warbler::Runtime::WAR_ENV); end
            end
          end
          env.extend Warbler::Runtime
          env.gem_path = @gem_path
          env.write_war_environment
          env.war_specs.each {|spec| @gems << spec }
        ensure
          if bundler_env_file
            class << Bundler
              alias env_file orig_env_file
            end
          end
        end
      else
        @bundler = false
      end
    end

    def default_jar_files
      require 'jruby-jars'
      require 'jruby-rack'
      FileList[JRubyJars.core_jar_path, JRubyJars.stdlib_jar_path, JRubyJars.jruby_rack_jar_path]
    end

    def auto_detect_frameworks
      return unless Warbler.framework_detection
      if File.exist?(".bundle/environment.rb")
        begin                     # Don't want Bundler to load from .bundle/environment
          mv(".bundle/environment.rb",".bundle/environment-save.rb", :verbose => false)
          auto_detect_rails || auto_detect_merb || auto_detect_rackup
        ensure
          mv(".bundle/environment-save.rb",".bundle/environment.rb", :verbose => false)
        end
      else
        auto_detect_rails || auto_detect_merb || auto_detect_rackup
      end
    end

    def auto_detect_rails
      return false unless task = Warbler.project_application.lookup("environment")
      task.invoke rescue nil
      return false unless defined?(::Rails)
      @dirs << "tmp" if File.directory?("tmp")
      @webxml.booter = :rails
      unless (defined?(Rails.vendor_rails?) && Rails.vendor_rails?) || File.directory?("vendor/rails")
        @gems["rails"] = Rails::VERSION::STRING
      end
      if defined?(Rails.configuration.gems)
        Rails.configuration.gems.each do |g|
          @gems << Gem::Dependency.new(g.name, g.requirement) if Dir["vendor/gems/#{g.name}*"].empty?
        end
      end
      if defined?(Rails.configuration.threadsafe!) &&
        (defined?(Rails.configuration.allow_concurrency) && # Rails 3
          Rails.configuration.allow_concurrency && Rails.configuration.preload_frameworks) ||
        (defined?(Rails.configuration.action_controller.allow_concurrency) && # Rails 2
         Rails.configuration.action_controller.allow_concurrency && Rails.configuration.action_controller.preload_frameworks)
        @webxml.jruby.max.runtimes = 1
      end
      true
    end

    def auto_detect_merb
      return false unless task = Warbler.project_application.lookup("merb_env")
      task.invoke rescue nil
      return false unless defined?(::Merb)
      @webxml.booter = :merb
      if defined?(Merb::BootLoader::Dependencies.dependencies)
        Merb::BootLoader::Dependencies.dependencies.each {|g| @gems << g }
      else
        warn "unable to auto-detect Merb dependencies; upgrade to Merb 1.0 or greater"
      end
      true
    end

    def auto_detect_rackup
      return false unless File.exist?("config.ru")
      @webxml.booter = :rack
      @webxml.rackup = File.read("config.ru")
      true
    end
  end

  # Helper class for holding arbitrary config.webxml values for injecting into +web.xml+.
  class WebxmlOpenStruct < OpenStruct
    %w(java com org javax).each {|name| undef_method name if Object.methods.include?(name) }

    def initialize(key = 'webxml')
      @key = key
      @table = Hash.new {|h,k| h[k] = WebxmlOpenStruct.new(k) }
    end

    def servlet_context_listener
      case self.booter
      when :rack
        "org.jruby.rack.RackServletContextListener"
      when :merb
        "org.jruby.rack.merb.MerbServletContextListener"
      else # :rails, default
        "org.jruby.rack.rails.RailsServletContextListener"
      end
    end

    def [](key)
      new_ostruct_member(key)
      send(key)
    end

    def []=(key, value)
      new_ostruct_member(key)
      send("#{key}=", value)
    end

    def context_params
      require 'cgi'
      params = {}
      @table.each do |k,v|
        case v
        when WebxmlOpenStruct
          nested_params = v.context_params
          nested_params.each do |nk,nv|
            params["#{CGI::escapeHTML(k.to_s)}.#{nk}"] = nv
          end
        else
          params[CGI::escapeHTML(k.to_s)] = CGI::escapeHTML(v.to_s)
        end
      end
      params.delete_if {|k,v| ['ignored', *ignored].include?(k.to_s) }
      params
    end

    def to_s
      "No value for '#@key' found"
    end
  end
end
