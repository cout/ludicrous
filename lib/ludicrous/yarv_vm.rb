# Older versions of Ruby 1.9 uses VM, but newer versions use RubyVM.  We
# always use RubyVM, so if we're running on an older version of the
# interpreter, we make RubyVM an alias for VM.
if defined?(VM) and not defined?(RubyVM) then
  RubyVM = VM
end

