module Util

	def putsStart(string)
		puts string.to_s + " - start"
	end

	def putsEnd(string)
		puts string.to_s + " - end"
	end


	module_function:putsStart
	module_function:putsEnd
end