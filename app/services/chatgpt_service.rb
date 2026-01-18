class ChatgptService
  def initialize
    @client = OpenAI::Client.new(
      access_token: ENV['OPENAI_API_KEY'],
      log_errors: true
    )
  end

  def chat(messages)
    system_message = {
      role: 'system',
      content: <<~TEXT
        あなたは飲食店検索アシスタントです。
        検索結果が提供された場合は、必ずその情報のみを使って回答してください。
        店名、URL、アクセス情報は一字一句変更せず、そのまま使用してください。
      TEXT
    }
    
    begin
      response = @client.chat(
        parameters: {
          model: 'gpt-3.5-turbo',
          messages: [system_message] + messages,
          temperature: 0.1,
          max_tokens: 1500
        }
      )
      
      response.dig('choices', 0, 'message', 'content')
    rescue => e
      Rails.logger.error "ChatGPT API Error: #{e.message}"
      "申し訳ございません。エラーが発生しました"
    end
  end
end