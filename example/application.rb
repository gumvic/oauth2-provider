dir = File.expand_path(File.dirname(__FILE__))
require dir + '/environment'

require 'sinatra'
require 'json'

set :static, true
set :public, dir + '/public'
set :views,  dir + '/views'

PERMISSIONS = {
  'read_notes' => 'Read all your notes'
}

ERROR_RESPONSE = JSON.unparse('error' => 'No soup for you!')

get('/') { erb(:home) }


#================================================================
# Register applications

get '/oauth/apps/new' do
  @client = OAuth2::Model::Client.new
  erb :new_client
end

post '/oauth/apps' do
  @client = OAuth2::Model::Client.new(params)
  @client.save ? redirect("/oauth/apps/#{@client.id}") : erb(:new_client)
end

get '/oauth/apps/:id' do
  @client = OAuth2::Model::Client.find_by_id(params[:id])
  erb :show_client
end


#================================================================
# OAuth 2.0 flow

# Initial request exmample:
# /oauth/authorize?response_type=token&client_id=7uljxxdgsksmecn5cycvug46v&redirect_uri=http%3A%2F%2Fexample.com%2Fcb&scope=read_notes
[:get, :post].each do |method|
  __send__ method, '/oauth/authorize' do
    respond_to_oauth { erb(:login) }
  end
end

post '/login' do
  @oauth2 = OAuth2::Provider.parse(request)
  @user = User.find_by_username(params[:username])
  erb(@user ? :authorize : :login)
end

post '/oauth/allow' do
  @user = User.find_by_id(params[:user_id])
  @auth = OAuth2::Provider::Authorization.new(params)
  if params['allow'] == '1'
    @auth.grant_access!(@user)
  else
    @auth.deny_access!
  end
  redirect @auth.redirect_uri
end


#================================================================
# Domain API

get '/me' do
  authorization = OAuth2::Provider.access_token(request)
  if authorization
    user = authorization.owner
    JSON.unparse('username' => user.username)
  else
    ERROR_RESPONSE
  end
end

get '/users/:username/notes' do
  verify_access :read_notes do |user|
    notes = user.notes.map do |n|
      {:note_id => n.id, :url => "#{host}/users/#{user.username}/notes/#{n.id}"}
    end
    JSON.unparse(:notes => notes)
  end
end

get '/users/:username/notes/:note_id' do
  verify_access :read_notes do |user|
    note = user.notes.find_by_id(params[:note_id])
    note ? note.to_json : JSON.unparse(:error => 'No such note')
  end
end



helpers do
  #================================================================
  # Generic handler for incoming OAuth requests
  def respond_to_oauth
    @oauth2 = OAuth2::Provider.parse(request)
    redirect @oauth2.redirect_uri if @oauth2.redirect?
        
    headers @oauth2.response_headers
    status  @oauth2.response_status
    
    @oauth2.response_body || yield
  end
  
  #================================================================
  # Check for OAuth access before rendering a resource
  def verify_access(scope)
    user  = User.find_by_username(params[:username])
    token = OAuth2::Provider.access_token(request)
    
    unless user and user.grants_access?(token, scope.to_s)
      return ERROR_RESPONSE
    end
    
    yield user
  end
  
  #================================================================
  # Return the full app domain
  def host
    request.scheme + '://' + request.host_with_port
  end
end

