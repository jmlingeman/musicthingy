# encoding: utf-8
require 'dl'
require 'dl/import'
module TaglibChecker
    extend DL::Importer
    dlload 'libtag_c.so'
    extern 'void* taglib_file_tag(void*)'
    extern 'void* taglib_file_new(char*)'
end

module ScanHelper
    class Scanner
        def scan_folder(folder)
            require 'rbrainz'
            require 'find'
            require 'taglib'


            artist_cache = Hash.new
            album_cache = Hash.new

            Find.find(folder) do |entry|
                begin
                    if [".mp3",".aac",".ogg",".mp4"].include?(entry[-4..-1].downcase)
                        puts check_file(entry)
                        if not check_file(entry)

                            puts "WARNING: Corrupt file.  Taglib cannot load it."
                            next
                        end

                        sleep(1) # To comply with MusicBrainz restrictions

                        mb_query = MusicBrainz::Webservice::Query.new
                        puts entry
                        # Check if we already have this album and artist uuid in
                        # cache to minimize queries to musicbrainz

                        artist_tag, album_tag, track_tag = get_tags(entry)
                        if artist_tag == nil and album_tag == nil and track_tag == nil
                            puts "Unable to read file", entry
                            next
                        end

                        if artist_cache[artist_tag] != nil
                            artist_name, artist_id, artist_score = artist_cache[artist_tag]
                        elsif artist_tag != nil and artist_tag.strip() != ""
                            artist_name, artist_id, artist_score = self.find_artist(mb_query, artist_tag)
                            artist_cache[artist_tag] = artist_name, artist_id, artist_score
                        else
                            artist_id = nil
                        end

                        if artist_id != nil and artist_score > 70
                            new_artist_tag = artist_name
                        else
                            puts "Too unsure of artist name.  Not tagging."
                            next
                        end

                        if album_cache[album_tag] != nil
                            album_name, album_id, album_score = album_cache[album_tag]
                        elsif album_tag != nil and album_tag.strip() != ""
                            album_name, album_id, album_score = self.find_album(mb_query, artist_id, album_tag)
                            album_cache[album_tag] = album_name, album_id, album_score
                        else
                            album_id = nil
                        end

                        if album_id != nil and album_score > 70
                            new_album_tag = album_name
                        else
                            puts "Too unsure of album name.  Not tagging."
                            next
                        end

                        # Get track from MB
                        track_name, track_id, track_score = self.find_track(mb_query, album_id, track_tag)

                        if track_id != nil and track_score > 70
                            new_track_tag = track_name
                        else
                            puts "Too unsure of track name.  Not tagging."
                            next
                        end

                        set_tags( entry, new_artist_tag, new_album_tag, new_track_tag )

                    end
                    #@artist = Artist.new(:name => entry, :path => folder+"/"+entry)
                rescue MusicBrainz::Webservice::RequestError
                    puts "Warning: Unable to read tags for file: %s, skipping." % entry
                end
                #@artist.save
                #puts @artist.errors
            end
        end

        def check_file(file)
            # This checks the file to make sure that it is valid, so taglib
            # won't segfault on us anymore
            #
            # Taken from http://www.ruby-forum.com/topic/215772


            taglib_file = TaglibChecker.taglib_file_new(file)

            if taglib_file.null?
                return false
            else
                return true
            end
        end

        def get_tags(file)
            tag = TagLib::File.new(file)
            if tag != nil
                artist_tag = self.format_string(tag.artist.to_s)
                album_tag = self.format_string(tag.album.to_s)
                track_tag = self.format_string(tag.title.to_s)

                # Have this be a regex string in the config file somewhere so the
                # user can set up how the directory is listed.

                tag.close()

                return artist_tag, album_tag, track_tag
            else # for some reason we got a null pointer to the file from taglib
                return nil, nil, nil
            end
        end

        def set_tags(file, artist_tag, album_tag, track_tag)
            tag = TagLib::File.new(file)

            tag.artist = artist_tag
            tag.album = album_tag
            tag.track = track_tag

            tag.save()
            tag.close()

        end

        def format_string(str)
            str.sub!("/"," ")
            str.strip!()
            return str
        end

        def find_artist(mb_query, artist_name)

            puts "Looking up artist in MusicBrainz artist entry for %s" % artist_name
            artist_filter = MusicBrainz::Webservice::ArtistFilter.new(:name => artist_name)
            puts artist_filter

            artists = mb_query.get_artists(artist_filter)

            artist = artists[0]
            artist_id = MusicBrainz::Model::MBID.new(artist.entity.id)

            new_name = artist.entity.name
            score = artist.score

            return new_name, artist_id.uuid, score
        end

        def find_album(mb_query, artist_id, album_name)

            album_filter = MusicBrainz::Webservice::ReleaseFilter.new(
                :artistid => artist_id,
                :title => album_name
            )
            puts "Fetching album data"
            albums = mb_query.get_releases(album_filter)

            if albums.size == 0
                puts "Album not found in MusicBrainz DB. Using current id3 tags."
                return nil
            end
            album = albums[0]
            puts "Found album %s, compared to current album %s" % [album.entity.title, album_name]

            album_id = MusicBrainz::Model::MBID.new(album.entity.id)
            new_title = album.entity.title

            return new_title, album_id.uuid, album.score
        end

        def find_track(mb_query, album_id, track_name)

            puts "Fetching track data"
            track_filter = MusicBrainz::Webservice::TrackFilter.new(
                :releaseid => album_id,
                :title => track_name
            )

            tracks = mb_query.get_tracks(track_filter)
            if tracks.size == 0
                puts "Track not found in MusicBrainz DB. Using current id3 tags."
                return nil
            end
            track = tracks[0]

            track_id = MusicBrainz::Model::MBID.new(track.entity.id)
            new_title = track.entity.title
            score = track.score

            puts track_id, new_title, score
            #puts "Found track %s, compared to current track %s" % [track.entity.title, track_name]
            return new_title, track_id.uuid, score

        end
    end
end

