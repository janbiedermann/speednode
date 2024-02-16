module Speednode
  class Runtime < ExecJS::Runtime
    def self.attach_proc(context_id, func, run_block)
      attached_procs[context_id] = { func => run_block }
    end

    def self.attached_procs
      @attached_procs ||= {}
    end

    def self.responders
      @responders ||= {}
    end

    attr_reader :name, :vm

    def initialize(options)
      @name        = options[:name]
      @binary      = ::Speednode::NodeCommand.cached(options[:command])
      @runner_path = options[:runner_path]
      @vm = VM.new(binary: @binary, source_maps: '--enable-source-maps', runner_path: @runner_path)
      @encoding    = options[:encoding]
      @deprecated  = !!options[:deprecated]
      @popen_options = {}
      @popen_options[:external_encoding] = @encoding if @encoding
      @popen_options[:internal_encoding] = ::Encoding.default_internal || 'UTF-8'
      @contexts = {} 
    end

    def register_context(uuid, context)
      @contexts[uuid] = context
    end

    def unregister_context(uuid)
      context = @contexts.delete(uuid)
      if context && @vm
        ObjectSpace.undefine_finalizer(context)
        @vm.delete_context(uuid) rescue nil # if delete_context fails, the vm exited before probably
      end
      @vm.stop if @contexts.size == 0 && @vm.started?
    end

    def stop_context(context)
      unregister_context(context.instance_variable_get(:@uuid))
    end

    def available?
      @binary ? true : false
    end

    def deprecated?
      @deprecated
    end
  end
end
