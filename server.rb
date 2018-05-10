require 'sinatra'
require 'httparty'
require 'securerandom'
require 'twilio-ruby'
require 'optimizely'
require 'json'

# STEP 1: Add the Optimizely Full Stack Ruby gem
# STEP 2: Require the Optimizely gem 
# STEP 3: Include the twilio account SID, auth token and phone number below

# => Log into Twilio and access the account SID, token, and number

#Optimizely Webhook Secret Key (do not store key in this file in a production environment)
SECRET_KEY = 'H8XKETaMasRpvc_YwTB1fJ7cYU4daf6mkM1fNKkuIxY'

# Optimizely Setup
# Step 4: Replace this url with your own Optimizely Project

DATAFILE_URL = 'https://cdn.optimizely.com/public/8688261308/s/10701100394_10701100394.json'
DATAFILE_URI_ENCODED = URI(DATAFILE_URL)

# => Step 5: Use a library, such as HTTParty, to get grab the datafile from the CDN 
#         https://github.com/jnunemaker/httparty#examples
#         example: response = HTTParty.get('http://api.stackexchange.com/2.2/questions?site=stackoverflow').body
#         The above line will return the body of the http request 
#         NOTE: use the uri encoded url shown above :)
response = HTTParty.get(DATAFILE_URI_ENCODED)
#puts "[CONSOLE LOG] #{response}"

# => Step 6: Initialize the Optimizely SDK using the json retrieved from step 4
#		  https://developers.optimizely.com/x/solutions/sdks/reference/?language=ruby
optimizely_client = Optimizely::Project.new(response)

# => Initializing the Twilio client to send sms messages
# => https://www.twilio.com/docs/libraries/ruby
TWILIO_CLIENT = Twilio::REST::Client.new TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN

get '/' do
  puts "[CONSOLE LOG]"
	'Welcome to the SE Full Stack training'
end

# => GET endpoint to receive messages, this should be setup as a webhook in Twilio
# => anytime twilio receives a message on our number, Twilio will make a request to this endpoint 
get '/sms' do
  
  # => Getting the number that texted the sms service
	sender_number = params[:From]
  
  # => Getting the message that was sent to the service
  # => We could use this to understand what the user said, and create a conversational dialog
	text_body = params[:Body]

  # => Outputing the number and text body to the ruby console
	puts "[CONSOLE LOG] New message from #{sender_number}"
	puts "[CONSOLE LOG] They said #{text_body}"
	puts "[CONSOLE LOG] Let's respond!"

	# =>  Randomly generate a new User ID to demonstrate bucketing
	# =>  Alternatively, you can use sender_number as the user ID, however due to deterministic bucketing using a single user id will always return the same variation
	user_id = SecureRandom.uuid

	# => STEP 7: Implement an Optimizely Full Stack experiment, or feature flag (with variables)
	# => Example, test out different messages in your response
	# => Using the helper function to reply to the number who messaged the sms service
  # => example: send_sms "Hey this is a response!" sender_number
    variation_key = optimizely_client.activate('sms_content_test', user_id)
    #variation = optimizely_client.get_variation('myexp', user_id)
    #puts "[CONSOLE LOG] Variation assignment #{variation}"
    
    feature_enabled = optimizely_client.is_feature_enabled('sms_content', user_id)
    if(feature_enabled)
        author = optimizely_client.get_feature_variable_boolean('sms_content', 'author', user_id)
        quote = optimizely_client.get_feature_variable_boolean('sms_content', 'quote', user_id)
        character = optimizely_client.get_feature_variable_boolean('sms_content', 'character', user_id)
        puts "[CONSOLE LOG] Features : Author #{author} Quote #{quote} Character #{character}"
    end
    
    
    if variation_key == 'seinfeld'
        #Seinfeld Content
        SEINFELD_URL = 'https://seinfeld-quotes.herokuapp.com/random'
        SEINFELD_URI_ENCODED = URI(SEINFELD_URL)
        seinfeld_quote = HTTParty.get(SEINFELD_URI_ENCODED)
        parsed_seinfeld = JSON.parse(seinfeld_quote)
        #Available information quote, author, season, episode, image
        if(quote)
            message = parsed_seinfeld['quote']
        end
        if(author)
            message = message + ' - ' + parsed_seinfeld['author'] 
        end
        if(character)
            message = message + ' - ' + parsed_seinfeld['character']
        end

        puts message
        
        #puts "[SEINFELD] #{parsed_seinfeld['quote']}"
    elsif variation_key == 'simpsons'
        #Simpsons Content
        SIMPSONS_URL = 'https://thesimpsonsquoteapi.glitch.me/quotes'
        SIMPSONS_URI_ENCODED = URI(SIMPSONS_URL)
        simpsons_quote = HTTParty.get(SIMPSONS_URI_ENCODED)
        #parsed_simpsons = JSON.parse(simpsons_quote.to_json)
        #Available information quote, character, image, direction
        puts "[SIMPSONS] #{simpsons_quote[0]['quote']}"
        if(quote)
            message = simpsons_quote[0]['quote']
        end
        if(author)
            message = message + ' - ' + simpsons_quote[0]['author'] 
        end
        if(character)
            message = message + ' - ' + simpsons_quote[0]['character']
        end
        puts message
    else
        message = "default"
    end
     
   
    
    #helper function was throwing errors so assembling message directly
    TWILIO_CLIENT.api.account.messages.create(
        from: TWILIO_NUMBER,
        to: sender_number,
        body: message
        )
end

# => BONUS: Implement a Optimizely webhooks to receive updates when your datafile changes & reinitialize the SDK

# Listen for webhook events sent by POST requests at this server's '/webhook' path.
#   Implement a secure webhook comparing the signatures.
# 
post '/webhook' do

  # The list entry data is located in the request body.
  request.body.rewind
  entry_data = request.body.read

  # Create a signature using this receiving server's secret key and the
  #   list entry's data it received. Note that the signature must be 
  #   prepended with "sha1="
  # 
  #secret_key = ENV['SECRET_KEY']
  secret_key = SECRET_KEY
  digest = OpenSSL::Digest.new('sha1')
  hexdigest = OpenSSL::HMAC.hexdigest(digest, secret_key, entry_data)

  # The signature sent from ShortStack is prepended with 'sha1=', so your
  #   signature must also be prepended with 'sha1=' for comparison
  #
  signature = 'sha1=' + hexdigest
    
  # Verify that the X-Ss-Signature header is encoded with the same 
  #   secret key that is stored on this receiving server by comparing
  #   the 'signature' variable above against the signature received from
  #   the ShortStack webhook request headers. If they do not match, this 
  #   server stops execution and returns a 500 error.
  #
  #   Note that it is more secure to use a utility such as secure_compare
  #   rather than the == operator
  # 
unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
    return halt 403, "Signatures didn't match!" 
 end

  # It is now safe to do something with the data. For example, print 
  #   the list entry's data to the console
  #
  #puts entry_data
    
    #Grab the latest version of the datafile and 
    response = HTTParty.get(DATAFILE_URI_ENCODED)
    puts "[CONSOLE LOG] #{response}"
    optimizely_client = Optimizely::Project.new(response)
    
end

# =>  Helper function to send a text message
# =>  The first parameter is the content of the text you wish to send
# =>  The second parameter is the number you wish to send the text to
def send_sms body, number
	TWILIO_CLIENT.api.account.messages.create(
      from: TWILIO_NUMBER,
      to: number,
      body: body
    ) 
end
