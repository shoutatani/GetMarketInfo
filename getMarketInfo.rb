
# **************************************************
# Crawling YahooFinance and get infomation
# and update DB with the data.
# Get with your favorite rating and days.
# **************************************************
# Date prepared : 2014-11-30
# Date updated : 2018-01-16
# Copyright (c) 2014 Shota Taniguchi
# Released under the MIT license
# http://opensource.org/licenses/mit-license.php
# **************************************************

require 'rubygems'
require "capybara"
require "capybara/dsl"
#require "selenium-webdriver"
require "capybara/poltergeist"
require "Date"
require 'digest/sha1'
require 'sqlite3'
require 'rexml/document'

class Crawler
	class YahooFinance
		include Capybara::DSL

		# Database name
		DATABASE_NAME = "marketCal.sqlite3"
		# Target Table name
		DATASTORE_TABLE_NAME = "TB_Ymarket"

		# get rating and days count of your preference from settings.xml
		def get_crawling_settings
			
			# ReadSettings from settings.xml file.
			doc = REXML::Document.new(open("./settings.xml"))

			# Get how many days you'd like to get. 
			@getDays = doc.elements['settings/getDays'].text
			if @getDays == nil || @getDays == "0"
				# the default is 5 days.
				@getDays = "5"
			end
			puts ""
			puts "Crawling Days : " + @getDays

			# Get type of the events.
			case doc.elements['settings/getImportance'].text
			when "1"
				@getImportance = "★"
			when "2"
				@getImportance = "★★"
			when "3"
				@getImportance = "★★★"
			else
				@getImportance = "すべて"
			end
			puts "Crawling rating : " + @getImportance

		end

		# Get settings and start by PhantomJS
		def init_crawling
			
			# Open Site
			page.driver.headers ={"User-Agent" => "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; Win64; x64; Trident/6.0)"}
			visit('/')
			puts ""
			puts "SiteOpen"

			# Open DataBase (create database file if not exists)
			@db = SQLite3::Database.new(DATABASE_NAME)

			# Create Target Table if it doesn't exist.
			if ! @db.execute("Select tbl_name from sqlite_master where type ='table';").flatten.include?(DATASTORE_TABLE_NAME)
				strCreate ="Create Table TB_Ymarket(id text primary key, event text, rating integer, date text);";
				@db.execute(strCreate)
			end
			puts ""
			puts "Connected to Database."

		end

		# waiting for ajax response(use this if the site uses ajax)
	    def wait_for_ajax(waitSeconds)
	      sleep waitSeconds
	      Timeout.timeout(Capybara.default_wait_time) do
	        active = page.evaluate_script("jQuery.active")
	        until active == 0
	          sleep 1
	          active = page.evaluate_script("jQuery.active")
	        end
	      end
	    end

	    # crawling site, and save it to database.
		def get_economic_calendar
			begin

				# get economic events  
				elapsed_days_count = 0
				start_day = Date.today
				while elapsed_days_count < @getDays.to_i
					
					# initialize start row count
					table_row_count = 0
					
					# Set Crawling Day
					crawling_target_day = start_day + elapsed_days_count
					date_input = "#{crawling_target_day.year.to_s}/#{crawling_target_day.month.to_s}/#{crawling_target_day.day.to_s}"
					date_hidden = crawling_target_day.strftime("%Y%m%d")

					# Search datapicker with css,and set the day to the Textbox
					find(".datepicker").set(date_input)

					# Set to the hidden element(by JavaScript)
					execute_script("document.getElementById('ymd').value = #{date_hidden}");

					# Search element with defined id(country), and select all country.
					find("#country").select("すべて")

					# Search element which name is 'i', and select value with getImportance
					select @getImportance, :from => 'i'
					
					# Execution Click
					click_button("selectBtn")

					# Set baseRowCount(the row count that starts getting infomation)
					baseTr = 2
					puts "----------------------------------------"
					# By XPath, find target table row.
					event_date = ''
					within(:xpath, %Q|//*[@id="main"]/div[3]/table/tbody/tr[#{baseTr + table_row_count}]|) do
						# get event day from source.
						event_date = all('th')[0].text.match(/\d+\/\d+/).to_s
						puts "getDay:" + event_date
					end

					# initialize the loop requirement
					enableLoop = true
					
					# get infomation until the next day
					table_row_count += 1
					while enableLoop == true do
						within(:xpath,%Q|//*[@id="main"]/div[3]/table/tbody/tr[#{baseTr + table_row_count}]|) do

							# initialize
							event_rate = 0
							unique_event_value = ""

							if has_css?(".yjMS")
								# no publication day
								enableLoop = false
								puts "発表なし"
								break
							elsif has_css?(".date")
								# reached to the next day
								enableLoop = false
								break
							else
								# when found valid event

								# get the event's time and content
								event_time = all('td')[0].text
								event_content = all('td')[1].text
								puts "Time:" + event_time
								puts "Event:" + event_content

								# get the event's rating
								if has_css?(".icoRating3")
									event_rate = 3
								elsif has_css?(".icoRating2")
									event_rate = 2
								elsif has_css?(".icoRating1")
									event_rate = 1
								else
									event_rate = 0
								end
								puts "Rating:" + event_rate.to_s

								# get month and day from event date
								event_month = event_date.match(/\d+/).to_s
								event_day = event_date.match(/\/(\d+)/)[1].to_s

								# create date object for insert the event data to datebase.
								if start_day.strftime("%m") == "12" && event_date.slice(0,2) == "1/"
									date_register = Date.new(start_day.year.to_i + 1,event_month.to_i,event_day.to_i)
								else
									date_register = Date.new(start_day.year.to_i,event_month.to_i,event_day.to_i)
								end

								# Register to DB if the time isn't undefined
								if event_time != "未定"

									event_hour = event_time.match(/\d+/).to_s
									event_minutes = event_time.match(/\:(\d+)/)[1].to_s

									# if the time is above p.m.25, add the day
									if event_hour.to_i >= 24
										date_register = date_register + 1
										event_hour = event_hour.to_i - 24
									end

									# for sqlite, create strings like a date object(sqlite doesn't have date type, but can control with only limited text format)
									defined_format_event_date = "#{date_register.strftime("%Y")}-#{date_register.strftime("%m")}-#{date_register.strftime("%d")} #{event_hour}:#{event_minutes}:00"
									puts defined_format_event_date

									# create sha1 to use the table key
									unique_event_value = Digest::SHA1.hexdigest(defined_format_event_date + event_content + event_rate.to_s);
									puts "SHA1:" + unique_event_value

									# search with the key, insert the infomatin if not exist.
									select_statement = "Select Count(0) from #{DATASTORE_TABLE_NAME.to_s} Where id = '#{unique_event_value}'"
									@db.execute(select_statement) do |row|
										if row[0].to_s == "0"
											strInsert ="Insert into #{DATASTORE_TABLE_NAME} Values('#{unique_event_value}','#{event_content}',#{event_rate},'#{defined_format_event_date}');"
											#Logic of Insert to Sqlite database
											@db.execute(strInsert)
											puts "Inserted to DB."
										else
											puts "Already registered."
										end
										puts "********************"
									end

								end

								table_row_count +=1

							end
						end
					end

					# after getting all infomation of the day, add the date count.
					elapsed_days_count+=1
					puts "----------------------------------------"
				end

			rescue => ex
				puts ex.message
				puts ex.backtrace
			ensure
				@db.close
			end

		end
	end
end

# Configure Capybara and get it started#

# for don't use RackApp
Capybara.run_server = false
# using Driver(default:default_driver ,the default is rack_test)
Capybara.current_driver = :poltergeist
# JavascriptDriver(default:Selenium)
Capybara.javascript_driver = :poltergeist
# target site
Capybara.app_host = %q|https://info.finance.yahoo.co.jp/fx/marketcalendar/|
# ajax_waiting time(seconds)
Capybara.default_max_wait_time = 5
# hidden_access(default:true ,unconcerned with changing the DOM with javascript)
Capybara.ignore_hidden_elements = true
# to ignore the javascript error
Capybara.register_driver(:poltergeist) do |app|
  Capybara::Poltergeist::Driver.new(app,{:timeout => 120,:js_errors => false})
end

puts "Started Crawling."

# create YahooFinance Crawler
yahoo_finace_crawler = Crawler::YahooFinance.new
# get settings and go to the site
yahoo_finace_crawler.get_crawling_settings
yahoo_finace_crawler.init_crawling
# get infomation and register data to database
yahoo_finace_crawler.get_economic_calendar

puts "Finished Crawling."