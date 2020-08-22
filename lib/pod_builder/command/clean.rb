require 'pod_builder/core'
require 'highline/import'

module PodBuilder
  module Command
    class Clean
      def self.call
        Configuration.check_inited
        PodBuilder::prepare_basepath

        install_update_repo = OPTIONS.fetch(:update_repos, true)
        installer, analyzer = Analyze.installer_at(PodBuilder::basepath, install_update_repo)
        all_buildable_items = Analyze.podfile_items(installer, analyzer)

        podspec_names = all_buildable_items.map(&:podspec_name)
        rel_paths = all_buildable_items.map(&:prebuilt_rel_path) + all_buildable_items.map(&:vendored_frameworks).flatten.map { |t| File.basename(t) }
        rel_paths.uniq!

        base_path = PodBuilder::prebuiltpath
        framework_files = Dir.glob("#{base_path}/**/*.framework")
        puts "Looking for unused frameworks".yellow
        clean(framework_files, base_path, rel_paths)

        rel_paths.map! { |x| "#{x}.dSYM"}

        Configuration.supported_platforms.each do |platform|
          base_path = PodBuilder::dsympath(platform)
          dSYM_files = Dir.glob("#{base_path}/**/*.dSYM")
          puts "Looking for #{platform} unused dSYMs".yellow    
          clean(dSYM_files, base_path, rel_paths)  
        end

        puts "Looking for unused sources".yellow
        clean_sources(podspec_names)

        puts "\n\n🎉 done!\n".green
        return 0
      end

      def self.clean_sources(podspec_names)        
        base_path = PodBuilder::basepath("Sources")

        repo_paths = Dir.glob("#{base_path}/*")

        paths_to_delete = []
        repo_paths.each do |path|
          podspec_name = File.basename(path)

          unless !podspec_names.include?(podspec_name)
            next
          end

          paths_to_delete.push(path)
        end

        paths_to_delete.flatten.each do |path|
          confirm = ask("#{path} unused.\nDelete it? [Y/N] ") { |yn| yn.limit = 1, yn.validate = /[yn]/i }
          if confirm.downcase == 'y'
            PodBuilder::safe_rm_rf(path)
          end
        end
      end

      private

      def self.clean(files, base_path, rel_paths)
        files = files.map { |x| [Pathname.new(x).relative_path_from(Pathname.new(base_path)).to_s, x] }.to_h

        paths_to_delete = []
        files.each do |rel_path, path|
          unless !rel_paths.include?(rel_path)
            next
          end

          paths_to_delete.push(path)
        end

        paths_to_delete.each do |path|
          confirm = ask("\n#{path} unused.\nDelete it? [Y/N] ") { |yn| yn.limit = 1, yn.validate = /[yn]/i }
          if confirm.downcase == 'y'
            PodBuilder::safe_rm_rf(path)
          end
        end

        Dir.chdir(base_path) do
          # Before deleting anything be sure we're in a git repo
          h = `git rev-parse --show-toplevel`.strip()
          raise "\n\nNo git repository found in current folder `#{Dir.pwd}`!\n".red if h.empty?    
          system("find . -type d -empty -delete") # delete empty folders
        end
      end
    end
  end
end
