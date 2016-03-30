# renamer.rb: main codebase for the media-renamer gem.
# Currently configured to only rename JPG and TIF files (using EXIFR to extract metadata)
# next major release will include support
require 'scrapers/image.rb'
require 'scrapers/music.rb'

module MediaOrganizer
  class FileNotValidError < StandardError; end
  class InvalidArgumentError < StandardError; end
  class UnsupportedFileTypeError < StandardError; end
  class RenameFailedError < StandardError; end

  # Renamer: primary class to use for renaming files. Allows renaming of a given list of files to a user-defined scheme based on each file's metadata.
  #
  #===Key Methods
  # 	*naming_scheme()
  # 	*generate()
  # 	*overwrite()
  #
  #===Example Usage
  #
  #	old_uris = ['./test/data/hs-2003-24-a-full_tif.tif']
  #
  #	scheme = ["Test-", :date_time]
  #
  #	r = Renamer.new()
  #
  #	r.set_naming_scheme(scheme)
  #
  #	new_uris = r.generate(old_uris)
  #
  #	r.overwrite(new_uris) #new filename: "./test/data/Test-2003-09-03 12_52_43 -0400.tif")
  #
  class Renamer
    DISALLOWED_CHARACTERS = /[\\:\?\*<>\|"\/]/	# Characters that are not allowed in file names by many file systems. Replaced with @subchar character.

    attr_reader	:naming_scheme	# Array of strings and literals used to construct filenames. Set thruough naming_scheme as opposed to typical/default accessor.
    attr_accessor	:subchar	# Character with which to substitute disallowed characters

    def initialize(_args = {})
      @naming_scheme = ['Renamed-default-']
      @subchar = '_'
    end

    # Renamer.naming_scheme(): sets the naming scheme for the generate method.
    #
    #===Inputs
    # 		1. Array containing strings and symbols.
    #
    #===Outputs
    # None (sets instance variable @naming_scheme)
    #
    #===Example
    # naming_scheme(["Vacation_Photos_", :date_taken]).
    # This will rename files into a format like "Vacation_Photos_2014_05_22.png" based on the file's date_taken metadata field.
    def set_naming_scheme(arr = [])
      @naming_scheme = set_scheme(arr)
    end

    # Renamer.generate(): Creates a hash mapping the original filenames to the new (renamed) filenames
    #
    #===Inputs
    # 		1. List of URIs in the form of an array
    # 		2. Optional hash of arguments.
    # 			*:scheme - array of strings and symbols specifying file naming convention
    #
    #===Outputs
    # Hash of "file name pairs." old_file => new_file
    def generate(uri_list = [], args = {})
      scheme = if !args[:scheme].nil? && args[:scheme].is_a?(Array) && !args[:scheme].empty?
                 set_scheme(args[:scheme])
               else
                 @naming_scheme
               end
      raise InvalidArgumentError unless !uri_list.nil? && uri_list.is_a?(Array)

      filename_pairs = {}
      uri_list.each do |i|
        new_string = handle_file(i, scheme)
        # If this is a valid file path, add it to the filename_pairs
        # puts "New file rename added: #{new_string}"
        filename_pairs[i] = new_string if !new_string.nil? && new_string != ''
      end

      return filename_pairs

    rescue InvalidArgumentError => arg_e
      puts arg_e
      puts 'Invalid arguments provided. Expected: uri_list = [], args = {}'
    rescue => e
      puts e.message
      puts e.backtrace.inspect
    end

    # Renamer.overwrite(): Writes new file names based upon mapping provided in hash argument. NOTE: this will create changes to file names!
    #
    #===Inputs
    # 		1. Hash containing mappings between old filenames (full URI) and new filenames (full URI). Example: {"/path/to/oldfile.jpg" => "/path/to/newfile.jpg"}
    #
    #===Outputs
    # none (file names are overwritten)
    def overwrite(renames_hash = {})
      renames_hash.each do |old_name, new_name|
        begin
          # error/integrity checking on old_name and new_name
          raise FileNotValidError, "Could not access specified source file: #{i}." unless old_name.is_a?(String) && File.exist?(old_name)
          raise FileNotValidError, 'New file name provided is not a string' unless new_name.is_a?(String)

          # puts (File.dirname(File.absolute_path(old_name)) + "/" + new_name) #Comment this line out unless testing
          File.rename(File.absolute_path(old_name), File.dirname(File.absolute_path(old_name)) + '/' + new_name)

        # check that renamed File.exist? - Commented out because this currently does not work.
        # unless new_name.is_a?(String) && File.exist?(new_name)
        #	raise RenameFailedError, "Could not successfuly rename file: #{old_name} => #{new_name}. Invalid URI or file does not exist."
        # end
        rescue => e
          puts "Ignoring rename for #{old_name} => #{new_name}"
        end
      end
    end

    # Routes metadata scrape based on file type (currently relies on extension - future version should use MIME)
    # currently assumes file was checked for validity in calling code.
    #
    #===Inputs
    # String containing full file URI (path and filename)
    #
    #===Outputs
    # Returns hash of metadata for file, or nil if none/error.
    def	get_metadata(file)
      # LOAD EXIF DATA
      case File.extname(file).downcase
      when '.jpg'
        Image.get_jpeg_data(file)
      when '.tif'
        Image.get_tiff_data(file)
      when '.mp3', '.wav', '.flac', '.aiff', '.ogg', '.m4a', '.asf'
        Music.get_music_data(file)
      else
        raise UnsupportedFileTypeError, "Error processing #{file}"
      end
    rescue UnsupportedFileTypeError => e
      puts "Could not process file: Extension #{File.extname(file)} is not supported."
      puts e.backtrace.inspect
    end

    private

    def handle_file(file, scheme)
      # Check file is real
      unless file.is_a?(String) && File.exist?(file)
        raise FileNotValidError, "Could not access specified file file: #{file}."
      end
      metadata = get_metadata(File.absolute_path(file))
      new_string = ''
      scheme.each do |j|
        if j.is_a?(String) then new_string += j
        elsif j.is_a?(Symbol)
          begin
            raise EmptyMetadataError if metadata[j].nil?
            new_string += metadata[j].to_s
          rescue => e
            puts "Could not get string for metadata tag provided in scheme: #{j} for file #{file}."
            puts "Ignoring file #{file}"
            return nil
          end
        end
      end
      return sub_hazardous_chars(new_string + File.extname(file))

    rescue FileNotValidError => e
      puts "Ignoring file #{file}"
      puts e
      return nil
    rescue => e
      puts e.message
      puts e.backtrace.inspect
      return nil
    end

    def set_scheme(input_arr = [])
      clean_scheme = []
      input_arr.each do |i|
        clean_scheme << i if i.is_a?(String) || i.is_a?(Symbol)
      end
      clean_scheme
    end

    def sub_hazardous_chars(str = '')
      str.gsub(DISALLOWED_CHARACTERS, @subchar)
    end
  end
end
