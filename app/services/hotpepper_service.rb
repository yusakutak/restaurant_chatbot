class HotpepperService
  include HTTParty
  base_uri 'http://webservice.recruit.co.jp/hotpepper/gourmet/v1/'

  def initialize
    @api_key = ENV['HOTPEPPER_API_KEY']
  end

  def search(params)
    query = {
      key: @api_key,
      budget: params[:budget],
      keyword: params[:keyword],
      lat: params[:lat],
      lng: params[:lng],
      range: params[:range] || 3,
      count: params[:count] || 10,
      format: 'json'
    }
    
    response = self.class.get('/', query: query.compact)
    
    # レスポンスが文字列の場合はJSONとしてパース
    if response.body.is_a?(String)
      JSON.parse(response.body)
    else
      response.parsed_response
    end
  rescue JSON::ParserError => e
    Rails.logger.error "JSON Parse Error: #{e.message}"
    { 'results' => { 'shop' => [] } }
  end
end