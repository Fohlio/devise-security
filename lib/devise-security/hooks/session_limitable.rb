# frozen_string_literal: true

# After each sign in, update unique_session_id. This is only triggered when the
# user is explicitly set (with set_user) and on authentication. Retrieving the
# user from session (:fetch) does not trigger it.
Warden::Manager.after_set_user except: :fetch do |record, warden, options|
  scope = options[:scope]

  if record.devise_modules.include?(:session_limitable) &&
     warden.authenticated?(options[:scope]) &&
     !record.skip_session_limitable? &&
     warden.env['rack.session']["devise_masquerade_#{scope}"].blank?
    unique_session_id = Devise.friendly_token
    warden.session(options[:scope])['unique_session_id'] = unique_session_id
    record.update_unique_session_id!(unique_session_id)
  end
end

# Each time a record is fetched from session we check if a new session from
# another browser was opened for the record or not, based on a unique session
# identifier. If so, the old account is logged out and redirected to the sign in
# page on the next request.
Warden::Manager.after_set_user only: :fetch do |record, warden, options|
  scope = options[:scope]
  env   = warden.request.env

  if record.devise_modules.include?(:session_limitable) &&
     warden.authenticated?(scope) &&
     options[:store] != false
    if record.unique_session_id != warden.session(scope)['unique_session_id'] &&
       !env['devise.skip_session_limitable'] &&
       !record.skip_session_limitable? &&
       warden.env['rack.session']["devise_masquerade_#{scope}"].blank?
      Rails.logger.warn do
        '[devise-security][session_limitable] session id mismatch: '\
        "expected=#{record.unique_session_id.inspect} "\
        "actual=#{warden.session(scope)['unique_session_id'].inspect}"
      end
      warden.raw_session.clear
      warden.logout(scope)
      throw :warden, scope: scope, message: :session_limited
    end
  end
end
