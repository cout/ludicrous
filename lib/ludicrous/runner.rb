require 'ludicrous'
require 'optparse'
require 'logger'

module JIT
  # TODO: Unused?
  module CompileDerivedClasses
    def inherited(klass)
      super(klass)
      klass.go_plaid
    end
  end
end

module Ludicrous

# The command-line version of ludicrous, which compiles all
# modules/methods in the system the.  This class is not normally invoked
# directly by the user.
class Runner
  COPYRIGHT = "TODO"
  VERSION = "TODO"

  # Called by the ludicrous executable to run an ruby program.
  #
  # +args+:: the ARGV that was passed to the ludicrous executable
  # +binding+:: a binding that was created at the toplevel
  # +toplevel_self+:: the toplevel self
  # +call_toplevel+:: a proc object that can be used to appply a
  # JIT::Function at the toplevel.
  def self.run(args, binding, toplevel_self, call_toplevel)
    runner = self.new(binding, toplevel_self, call_toplevel)
    runner.parse(args)
    return runner.run
  end

  # Create a new Ludicrous::Runner.
  #
  # +binding+:: a binding that was created at the toplevel
  # +toplevel_self+:: the toplevel self
  # +call_toplevel+:: a proc object that can be used to appply a
  # JIT::Function at the toplevel.
  def initialize(binding, toplevel_self, call_toplevel)
    @binding = binding
    @call_toplevel = call_toplevel
    @toplevel_self = toplevel_self
    @dash_e = []
    @require = []
    @cd = nil
    @options = Ludicrous::CompileOptions.new
    @ruby_prof = false
    @ruby_prof_printer = "FlatPrinter"
    @ruby_prof_file = nil
  end

  # Parse the command-line arguments.
  #
  # +args+:: the ARGV that was passed to the ludicrous executable
  def parse(args)
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [switches] [--] [programfile] [arguments]"
      opts.summary_width = 15
      opts.summary_indent = '  '

      opts.on(
          "-e line",
          "one line of script. Several -e's allowed. Omit [programfile]") do |line|
        @dash_e << line
      end

      opts.on(
          "-I path",
          "specify $LOAD_PATH directory (may be used more than once)") do |dir|
        $: << dir
      end

      opts.on(
          "-r library",
          "require the library, before executing your script") do |feature|
            puts "Turning on warnings"
        @require << feature
      end

      opts.on(
          "-v",
          "print version number, then turn on verbose mode") do |verbose|
            puts "Turning on warnings"
        puts VERSION
        $VERBOSE = verbose
      end

      opts.on(
          "-w",
          "turn on warnings for your script") do |verbose|
            puts "Turning on warnings"
        $VERBOSE = verbose
      end

      opts.on(
          "-C directory",
          "cd to directory, before executing your script") do |dir|
        @cd = dir
      end

      opts.on_tail(
          "--jit-log[=lvl]",
          "turn on logging for JIT compilation") do |lvl|
        enable_jit_log(lvl)
      end

      opts.on_tail(
          "--precompile",
          "precompile all methods instead of installing stubs") do |p|
        @options.precompile = p
      end

      opts.on_tail(
          "-O level",
          "set the optimization level") do |o|
        @options.optimization_level = o
      end

      opts.on_tail(
          "--ruby-prof",
          "use the ruby-prof profiler") do |p|
        @ruby_prof = p
      end

      opts.on_tail(
          "--prof-fmt=p",
          "format profiler output with printer p") do |p|
        @ruby_prof_printer = p
      end

      opts.on_tail(
          "--prof-out=file",
          "write profiler output to file") do |file|
        @ruby_prof_file = file
      end

      opts.on_tail(
          "--copyright",
          "print the copyright and exit") do
        puts COPYRIGHT
        exit()
      end

      opts.on_tail(
          "--version",
          "print the version and exit") do
        puts VERSION
        exit()
      end

      opts.on_tail(
          "-h",
          "--help",
          "show this help message and exit") do
        puts opts.banner
        opts.instance_eval do
          visit(:each_option) do |o|
            left = (o.short + o.long).join(', ')
            left << o.arg if o.arg
            left = left.ljust(opts.summary_width)
            right = o.desc
            # p o
            puts "  #{left} #{right}"
          end
        end
        exit()
      end

      opts.order!(args) do |arg|
        args.unshift arg
        opts.terminate
      end
    end
  end

  # Turn on JIT logging for levels +lvl+ and above.
  #
  # +lvl+:: the minimum level to log
  def enable_jit_log(lvl)
    Ludicrous.logger = Logger.new(STDERR)
    Ludicrous.logger.formatter = proc { |level, time, progname, msg|
      "#{level}: #{msg}\n"
    }
    if(lvl)
      Ludicrous.logger.level = Logger.const_get(lvl.upcase)
    end
  end

  # Turn on JIT for all modules in the system.  If precompiling is
  # enabled, they will be compiled now, otherwise a stub method is
  # installed now and each method will be compiled the first time it is
  # called.
  def jit_compile_all_modules
    # TODO: Not sure why this one has to come first...
    jit_compile_module(Module)

    # We'll have to compile these anyway
    jit_compile_module(Ludicrous::JITCompiled)
    jit_compile_module(Kernel)
    jit_compile_module(JIT::Value)
    jit_compile_module(JIT::Function)
    jit_compile_module(Node)
    jit_compile_module(MethodSig)
    jit_compile_module(Method)
    jit_compile_module(UnboundMethod)

    ObjectSpace.each_object(Module) do |m|
      jit_compile_module(m) if m != Object
    end

    # Compile this one last
    jit_compile_module(Object)
  end

  # Turn on JIT for a specific module using +Module#go_plaid+.
  #
  # +m+:: the module to enable JIT compilation for.
  def jit_compile_module(m)
    m.go_plaid(@options)
  end

  # Run the program that was passed to the ludicrous executable.
  def run
    if @ruby_prof then
      begin
        require 'rubygems'
      rescue LoadError
      end
      require 'ruby-prof'

      result = RubyProf.profile { run_ }

      if @ruby_prof_printer =~ /Printer$/ then
        printer_name = @ruby_prof_printer
      else
        printer_name = @ruby_prof_printer + "Printer"
      end

      printer = RubyProf.const_get(printer_name).new(result)

      if @ruby_prof_file then
        File.open(@ruby_prof_file, 'w') do |out|
          printer.print(out, 0)
        end
      else
        printer.print(STDOUT, 0)
      end
    else
      # TODO: fix the backtrace if an exception is raised
      run_
      exit()
    end
  end

  def run_
    jit_compile_all_modules

    if @cd then
      Dir.chdir @cd
    end

    @require.each do |feature|
      require feature
    end

    if @dash_e.size > 0 then
      program = @dash_e.join("\n")
      return run_toplevel(program, '-e')
    elsif ARGV[0].nil? or ARGV[0] == '-'
      ARGV.shift
      program = STDIN.read
      $0.replace('-')
      return run_toplevel(program, '-')
    else
      filename = ARGV.shift
      program = File.read(filename)
      $0.replace(filename)
      return run_toplevel(program, filename)
    end
  end
  private :run_

  # Run the given program at the toplevel as a compiled program if
  # possible, or as an interpreted program if compilation fails.
  #
  # +program+:: a String containing the program to be run
  # +filename+:: the filename of the program to be run
  def run_toplevel(program, filename)
    if f = compile_toplevel(program, filename) then
      return run_toplevel_compiled(f)
    else
      return run_toplevel_interpreted(program, filename)
    end
  end

  # Run the given program at the toplevel as a compiled program.
  #
  # +f+:: a JIT::Function with the compiled toplevel program
  def run_toplevel_compiled(f)
    @call_toplevel.call(f)
  end

  # Run the given program at the toplevel as an interpreted program.
  #
  # +program+:: a String containing the program to be run
  # +filename+:: the filename of the program to be run
  def run_toplevel_interpreted(program, filename)
    eval(program, @binding, filename)
  end

  # Compile the given toplevel program.
  #
  # +program+:: a String containing the program to be run
  # +filename+:: the filename of the program to be run
  def compile_toplevel(program, filename)
    f = nil
    begin
      Ludicrous.logger.info "Compiling toplevel..."
      node = Node.compile_string(program, filename)
      f = node.ludicrous_compile_toplevel(@toplevel_self)
      Ludicrous.logger.info "Toplevel succeeded"
      return f
    rescue
      Ludicrous.logger.error "Toplevel failed: #{$!} (#{$!.backtrace[0]})"
      return nil
    end
  end
end

end # module Ludicrous
