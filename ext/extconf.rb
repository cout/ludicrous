require 'mkmf'

if not have_library('jit', 'jit_init', []) then
  $stderr.puts "libjit not found"
  exit 1
end

require 'jit'

if not have_header('rubyjit.h') then
  # ruby-libjit's setup.rb will install rubyjit.h into ruby's include
  # directory; if it didn't, then perhaps we are using rubygems
  require 'rubygems'
  s = nil
  begin
    s = Gem::Specification.find_by_name('ruby-libjit')
  rescue Gem::LoadError
    $stderr.puts "Could not find rubyjit.h and could not find ruby-libjit gem"
    exit 1
  end
  $CPPFLAGS.gsub!(/^/, "-I#{s.full_gem_path}/ext ")
  p $CPPFLAGS
end


have_func("rb_errinfo", "ruby.h")

if have_struct_member("struct RObject", "iv_tbl", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_ROBJECT_IV_TBL"
end

if have_struct_member("struct RObject", "as", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_ROBJECT_AS"
end

if have_struct_member("struct RClass", "iv_tbl", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RCLASS_IV_TBL"
end

if have_struct_member("struct RFloat", "value", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RFLOAT_VALUE"
end

if have_struct_member("struct RString", "len", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RSTRING_LEN"
end

if have_struct_member("struct RString", "ptr", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RSTRING_PTR"
end

if have_struct_member("struct RArray", "len", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RARRAY_LEN"
end

if have_struct_member("struct RArray", "as.heap.len", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RARRAY_AS_HEAP_LEN"
end

if have_struct_member("struct RArray", "as.heap.ptr", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RARRAY_AS_HEAP_PTR"
end

if have_struct_member("struct RArray", "as.ary", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RARRAY_AS_ARY"
end

if have_struct_member("struct RArray", "ptr", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RARRAY_PTR"
end

if have_struct_member("struct RRegexp", "len", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RREGEXP_LEN"
end

if have_struct_member("struct RRegexp", "ptr", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RREGEXP_PTR"
end

if have_struct_member("struct RHash", "tbl", "ruby.h") then
  $defs[-1] = "-DHAVE_ST_RHASH_TBL"
end

have_type("struct FRAME", [ "ruby.h", "env.h" ])
have_type("struct SCOPE", [ "ruby.h", "env.h" ])

if have_header('ruby/node.h') then
  # ruby.h defines HAVE_RUBY_NODE_H, even though it is not there
  $defs.push("-DREALLY_HAVE_RUBY_NODE_H")
elsif have_header('node.h') then
  # okay
else
  $defs.push("-DNEED_MINIMAL_NODE")
end

rb_files = Dir['*.rb']
rpp_files = Dir['*.rpp']
generated_files = rpp_files.map { |f| f.sub(/\.rpp$/, '') }

srcs = Dir['*.c']
generated_files.each do |f|
  if f =~ /\.c$/ then
    srcs << f
  end
end
srcs.uniq!
$objs = srcs.map { |f| f.sub(/\.c$/, ".#{$OBJEXT}") }
$CFLAGS << ' -Wall -g'

create_makefile("ludicrous_ext")

append_to_makefile = ''

rpp_files.each do |rpp_file|
dest_file = rpp_file.sub(/\.rpp$/, '')
append_to_makefile << <<END
#{dest_file}: #{rpp_file} #{rb_files.join(' ')}
	$(RUBY) rubypp.rb #{rpp_file} #{dest_file}
END
end

generated_headers = generated_files.select { |x| x =~ /\.h$/ || x =~ /\.inc$/ }
append_to_makefile << <<END
$(OBJS): #{generated_headers.join(' ')}
clean: clean_generated_files
clean_generated_files:
	@$(RM) #{generated_files.join(' ')}
END

File.open('Makefile', 'a') do |makefile|
  makefile.puts(append_to_makefile)
end

