# coding: utf-8

=begin
**************************************************
Crawling YahooFinance and get infomation
and update DB with the data.
**************************************************
Get with your favorite rating and days.
**************************************************
Date prepared : 2014-11-30
Date updated :
Copyright (c) 2014 Shota Taniguchi
Released under the MIT license
http://opensource.org/licenses/mit-license.php
**************************************************
=end
require 'rubygems'
require "capybara"
require "capybara/dsl"
#require "selenium-webdriver"
require "capybara/poltergeist"
require "Date"
require 'digest/sha1'
require 'sqlite3'
require 'rexml/document'
require './Util.rb'

class Crawler
		class YahooFinance
			include Capybara::DSL #include DSL for using Page Method(return automatically initialized Session Object)
			include Util #include my utilities

			#Constants
			#undefined time
			C_STR_UNDEFINED = "未定"
			#Database name
			C_STR_DB_NAME = "marketCal.sqlite3"
			#Table name
			C_STR_TB_Ymarket = "TB_Ymarket"

			#Get settings and start by PhantomJS
			def login
				putsStart __method__
				getSettings
				#"driver"method is undefined in DSL_METHODS、so use Page method.
				page.driver.headers ={"User-Agent" => "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; Win64; x64; Trident/6.0)"}
				putsStart "siteOpen"
				#go to your specified site
				visit('/')
				putsEnd __method__
			end

			#get rating and days count of your preference from settings.xml
			def getSettings
				putsStart __method__
				doc = REXML::Document.new(open("./settings.xml"))
				@getDays = doc.elements['settings/getDays'].text
				if @getDays == "0" || @getDays == nil
					@getDays = "5"
				end

				puts "Crawling Days : " + @getDays

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
				putsEnd __method__
			end

			#waiting for ajax(use this if the site uses ajax)
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

	    #指標カレンダー取得メソッド
			def getEconomicCalendar
				begin
					putsStart __method__
					#DBOpen
					@db = SQLite3::Database.new(C_STR_DB_NAME)
					#Tableが存在しなければ作成
					if @db.execute("Select tbl_name from sqlite_master where type ='table';").flatten.include?(C_STR_TB_Ymarket)
					else
						strCreate ="Create Table TB_Ymarket(id text primary key,event text,rating integer,date text);";
						@db.execute(strCreate)
					end
					puts "Connected to Database."

					#FromToday,get infomation for your specified days
					@iDateCnt = 0
					while @iDateCnt < @getDays.to_i
						#initialize start row count
						iRowCnt = 0
						dateToday = Date.today
						#Set Crawling Day
						dateToday = dateToday + @iDateCnt
						@strTodayForDateTextBox = "#{dateToday.year.to_s}/#{dateToday.month.to_s}/#{dateToday.day.to_s}"
						@strTodayForDateHidden = dateToday.strftime("%Y%m%d")

						#Search datapicker with css,and set the day to the Textbox
						find(".datepicker").set(@strTodayForDateTextBox)
						#Set to the hidden element(by javascript)
						execute_script("document.getElementById('ymd').value = #{@strTodayForDateHidden}");
						#Search element with defined id(country),and select
						find("#country").select("すべて")
						#Search element by name of i,select with getImportance
						select @getImportance,:from => 'i'

						#**execution click**
						click_button("selectBtn")

						#set baseRowCount(the row count that starts getting infomation)
						baseTr = 2

						puts "----------------------------------------"

						#within has same SearchOption to find method,and uses the block.
						within(:xpath,%Q|//*[@id="main"]/div[3]/table/tbody/tr[#{baseTr + iRowCnt}]|) do
							#get actual day form source.
							@rawToday = all('th')[0].text
							@rawToday = @rawToday.match(/\d+\/\d+/).to_s
							puts "getDay:" + @rawToday
						end

						#for reading next row
						iRowCnt +=1
						#initialize  the loop requirement
						enableLoop = true

						#get infomation until the next day
						while enableLoop == true do
							within(:xpath,%Q|//*[@id="main"]/div[3]/table/tbody/tr[#{baseTr + iRowCnt}]|) do

								#initialize
								iRating = 0
								sSHA1ID = ""

								if has_css?(".yjMS")#no publication day
									enableLoop = false
									puts "発表なし"
									break
								elsif has_css?(".date")#reached to the next day
									enableLoop = false
									break
								else
									#getTime
									strRawTime = all('td')[0].text
									#getEvent
									strRawEvent = all('td')[1].text
									puts "Time:" + strRawTime
									puts "Event:" + strRawEvent

									#getRating
									if has_css?(".icoRating3")
										iRating = 3
									elsif has_css?("icoRating2")
										iRating = 2
									elsif has_css?("icoRating1")
										iRating = 1
									else
										iRating = 0
									end
									puts "Rating:" + iRating.to_s

									#get Month and day from actual day
									strTargetMonth = @rawToday.match(/\d+/).to_s
									strTargetDay =@rawToday.match(/\/(\d+)/)[1].to_s

									#if the month of today is December,and actual month is the month of next Year,add the year and create the date object for using sqlite
									if dateToday.strftime("%m") == "12" && @rawToday.slice(0,2) == "1/"
										dateRegister = Date.new(dateToday.year.to_i + 1,strTargetMonth.to_i,strTargetDay.to_i)
									else
										dateRegister = Date.new(dateToday.year.to_i,strTargetMonth.to_i,strTargetDay.to_i)
									end

									#Register to DB if the time isn't undefined
									if strRawTime != C_STR_UNDEFINED
										strTargetHour = strRawTime.match(/\d+/).to_s
										strTargetMinutes = strRawTime.match(/\:(\d+)/)[1].to_s

										#if the time is above p.m.25,add the day
										if strTargetHour.to_i >= 24
											dateRegister = dateRegister + 1
											strTargetHour = strTargetHour.to_i - 24
										end

										#for sqlite,Create strings like a date object(sqlite doesn't have date type,but controll with only limited text format.)
										strDBDate = "#{dateRegister.strftime("%Y")}-#{dateRegister.strftime("%m")}-#{dateRegister.strftime("%d")} #{strTargetHour}:#{strTargetMinutes}:00"
										puts strDBDate

										#creat sha1 to use the DB key
										sSHA1ID = Digest::SHA1.hexdigest(strDBDate + strRawEvent + iRating.to_s);
										puts "SHA1:" + sSHA1ID

										#Search with the key,insert the infomatin if the count is zero.
										sqlSelect = "select count(*) from #{C_STR_TB_Ymarket.to_s} where id = '#{sSHA1ID}'"
										@db.execute(sqlSelect) do |row|
											if row[0].to_s == "0"
												strInsert ="Insert into #{C_STR_TB_Ymarket} values('#{sSHA1ID}','#{strRawEvent}',#{iRating},'#{strDBDate}');"
												#Logic of Insert to Sqlite database
												@db.execute(strInsert)
												puts "Insert to DB"
											else
												puts "Already registered"
											end
											puts "********************"
										end#do

									end#if - undefined

									iRowCnt +=1

							end#if - has_css
						end#with_in - do
					end#while_enable_loop
					#get all infomation of the day,add the date count.
					@iDateCnt+=1
					puts "----------------------------------------"
				end#while_datecnt

			rescue => ex
				puts ex.message
				puts ex.backtrace
			ensure
				@db.close
				putsEnd __method__
			end
		end#def_eco
	end#class_YahooFinance
end#class_Crawler



#Configure Capybara and get it started#

#for don't use RackApp
Capybara.run_server = false
#using Driver(default:default_driver ,the default is rack_test)
Capybara.current_driver = :poltergeist
#JavascriptDriver(default:Selenium)
Capybara.javascript_driver = :poltergeist
#target site
Capybara.app_host = %q|http://info.finance.yahoo.co.jp/fx/marketcalendar|
#ajax_waiting time(seconds)
Capybara.default_wait_time = 5
#hidden_access(default:true ,unconcerned with changing the DOM with javascript)
Capybara.ignore_hidden_elements = true
#to ignore the javascript error
Capybara.register_driver(:poltergeist) do |app|
  Capybara::Poltergeist::Driver.new(app,{:timeout => 120,:js_errors => false})
end

#Create YahooFInance Crawler
_crawler = Crawler::YahooFinance.new
#get settings and go to the site
_crawler.login
#get infomation and register with sqlite
_crawler.getEconomicCalendar
