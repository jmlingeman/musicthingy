module ScanHelper
    class Scanner
        def scan_folder(folder)
            require 'rbrainz'
            require 'find'
            require 'taglib'

            mb_query = MusicBrainz::Webservice::Query.new

            artist_cache = Hash.new
            album_cache = Hash.new

            Find.find(folder) do |entry|
                if entry.downcase.include?(".mp3")
                    puts entry
                    tag = TagLib::File.new(entry)

                    artist_tag = tag.artist.to_s
                    album_tag = tag.album.to_s
                    track_tag = tag.title.to_s
                    # Check if we already have this album and artist uuid in
                    # cache to minimize queries to musicbrainz

                    if artist_cache[artist_tag] != nil
                        artist_name, artist_id, artist_score = artist_cache[artist_tag]
                    else
                        artist_name, artist_id, artist_score = self.find_artist(mb_query, artist_tag)
                        artist_cache[artist_tag] = artist_name, artist_id, artist_score
                    end

                    if artist_id != nil and artist_score > 70
                        tag.artist = artist_name
                        tag.save
                    else
                        puts "Too unsure of artist name.  Not tagging."
                        next
                    end

                    if album_cache[album_tag] != nil
                        album_name, album_id, album_score = album_cache[album_tag]
                    else
                        album_name, album_id, album_score = self.find_album(mb_query, artist_id, album_tag)
                        album_cache[album_tag] = album_name, album_id, album_score
                    end

                    if album_id != nil and album_score > 70
                        tag.album = album_name
                        tag.save
                    else
                        puts "Too unsure of album name.  Not tagging."
                        next
                    end

                    # Get track from MB
                    track_name, track_id, track_score = self.find_track(mb_query, artist_id, album_id, track_tag)

                    if track_id != nil and track_score > 70
                        tag.title = track_name
                        tag.save
                    else
                        puts "Too unsure of track name.  Not tagging. Score: %i" % track_score
                        next
                    end
                end
                #@artist = Artist.new(:name => entry, :path => folder+"/"+entry)
                #@artist.save
                #puts @artist.errors
            end
        end


        def find_artist(mb_query, artist_name)

            puts "Looking up artist in MusicBrainz artist entry for %s" % artist_name
            artist_filter = MusicBrainz::Webservice::ArtistFilter.new(:name => artist_name)

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

        def find_track(mb_query, artist_id, album_id, track_name)

            puts "Fetching track data"
            track_filter = MusicBrainz::Webservice::TrackFilter.new(
                :releaseid => album_id,
                :artistid => artist_id,
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
            puts "Found track %s, compared to current track %s" % [track.entity.title, track_name]
            return new_title, track_id.uuid, score

        end
    end
end

