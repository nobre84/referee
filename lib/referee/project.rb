module Referee
  # Helper subclass of `Xcode::Project`.
  # Provides accessors into resources, etc.
  class Project < ::Xcodeproj::Project
    STORYBOARD_FILETYPE = 'file.storyboard'
    VIEW_CONTROLLER_TAGS = %w(viewController
                              tableViewController
                              navigationController
                              glkViewController
                              pageViewController
                              collectionViewController
                              splitViewController
                              avPlayerViewController
                              tabBarController)

    DEFAULT_VIEW_CONTROLLER_TYPES = %w(
      UIViewController
      UITableViewController
      UINavigationController
      GLKViewController
      UIPageViewController
      UICollectionViewController
      UISplitViewController
      AVPlayerViewController
      UITabBarController
    )

    VIEW_CONTROLLER_TYPE_MAP = Hash[VIEW_CONTROLLER_TAGS.zip(DEFAULT_VIEW_CONTROLLER_TYPES)]

    attr_accessor :config, :resources

    # Instantiate a new `Project` instance given a `Configuration`.
    def self.new_with_config(config)
      project = new(config.project)
      project.initialize_from_file
      project.config = config
      project.parse_project
      project
    end

    def parse_project
      @resources = []

      find_storyboards.each do |storyboard|
        # Parse out XML representation.
        xml = storyboard_xml(storyboard)
        table_cells = table_cells(xml)
        collection_cells = collection_cells(xml)
        view_controllers = view_controllers(xml)
        non_empty_view_controllers = view_controllers.compact.uniq
        segues = segues(xml)

        # Add to resources collection
        group = ResourceGroup.new(storyboard, table_cells, collection_cells, non_empty_view_controllers, segues, @config)
        @resources << group

        # Check for missing view controller IDs in this storyboard.
        if non_empty_view_controllers.count != view_controllers.count
          msg = "Missing view controller ID(s) in '#{group.storyboard_name}' storyboard!"

          if @config.error_on_missing_storyboard_ids
            build_output.die msg
          else
            build_output.warn msg
          end
        end
      end
    end

    private

    # Search project for files matching the known storyboard type.
    def find_storyboards
      all_files = files
      all_files.keep_if { |f| f.last_known_file_type == STORYBOARD_FILETYPE }
    end

    def storyboard_xml(storyboard)
      file = File.open(storyboard.real_path)
      Nokogiri::XML(file)
    end

    def table_cells(xml)
      cells = xml.css('tableViewCell')
      cells.map { |n| n['reuseIdentifier'] }.compact.uniq
    end

    def collection_cells(xml)
      cells = xml.css('collectionViewCell')
      cells.map { |n| n['reuseIdentifier'] }.compact.uniq
    end

    def view_controllers(xml)
      selector = VIEW_CONTROLLER_TAGS.join(',')
      controllers = xml.css(selector)
      controllers_list = controllers.map do |n|
        tag_name = n.name
        identifier = n['storyboardIdentifier']
        klass = n['customClass'] || VIEW_CONTROLLER_TYPE_MAP[tag_name]
        { identifier: identifier, class: klass }
      end
      controllers_list.delete_if { |c| c[:identifier].nil? || c[:identifier].strip.empty? }
      controllers_list
    end

    def segues(xml)
      segues = xml.css('segue').map { |n| n['identifier'] }
      segues.delete_if { |item| item.nil? || item.strip.empty? }
      segues.uniq
    end

    def build_output
      @build_output ||= BuildOutput.new(@config)
    end
  end
end
