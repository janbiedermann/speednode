module Speednode
  class << self
    attr_accessor :node_paths

    def set_node_paths
      np_sep = Gem.win_platform? ? ';' : ':'
      existing_node_path = ENV['NODE_PATH']
      temp_node_path = ''
      if existing_node_path.nil? || existing_node_path.empty?
        temp_node_path = Speednode.node_paths.join(np_sep)
      else
        if existing_node_path.end_with?(np_sep)
          temp_node_path = existing_node_path + Speednode.node_paths.join(np_sep)
        else
          temp_node_path = existing_node_path + np_sep + Speednode.node_paths.join(np_sep)
        end
      end
      ENV['NODE_PATH'] = temp_node_path.split(np_sep).uniq.join(np_sep)
    end
  end

  self.node_paths = []
end
