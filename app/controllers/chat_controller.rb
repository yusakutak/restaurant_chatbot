class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  # クラス変数で会話履歴を保持（本番環境では別の方法を使用）
  @@conversations = {}

  def index
    session_id = session.id.to_s
    @@conversations[session_id] ||= []
    @messages = @@conversations[session_id]
  end

def create
  session_id = session.id.to_s
  @@conversations[session_id] ||= []
  @@shown_shops ||= {}
  @@shown_shops[session_id] ||= []
  @@all_search_results ||= {}
  @@all_search_results[session_id] ||= []
  
  user_message = params[:message]
  
  # リセット
  if user_message.match?(/リセット|最初から|新しく/)
    @@conversations[session_id] = []
    @@shown_shops[session_id] = []
    @@all_search_results[session_id] = []
  end
  
  @@conversations[session_id] << { role: 'user', content: user_message }

  begin
    # 新規検索が必要か判断
    needs_new_search = should_search?(user_message) && 
                      !user_message.match?(/他|別|候補|もっと|ほか|以外/)
    
    if needs_new_search
      # 新しい検索を実行
      search_params = extract_search_params(user_message)
      hotpepper = HotpepperService.new
      restaurants_data = hotpepper.search(search_params)
      
      Rails.logger.info "===== ホットペッパーAPI検索実行 ====="
      Rails.logger.info "店舗数: #{restaurants_data.dig('results', 'shop')&.length || 0}"
      if restaurants_data.dig('results', 'shop')&.any?
        restaurants_data.dig('results', 'shop').each_with_index do |shop, i|
          Rails.logger.info "#{i+1}. #{shop['name']}"
        end
      end
      Rails.logger.info "=================================="
      
      # 全検索結果を保存
      @@all_search_results[session_id] = restaurants_data.dig('results', 'shop') || []
      @@shown_shops[session_id] = []
    end
    
    # 表示する店を選択
    if @@all_search_results[session_id].any?
      # まだ表示していない店を取得
      remaining_shops = @@all_search_results[session_id].reject do |shop|
        @@shown_shops[session_id].include?(shop.dig('urls', 'pc'))
      end
      
      # 残りがなければリセット
      if remaining_shops.empty?
        @@shown_shops[session_id] = []
        remaining_shops = @@all_search_results[session_id]
        response_text = "全ての検索結果を表示しました。最初に戻ります。\n\n"
      else
        response_text = ""
      end
      
      # 次の3店舗を取得
      shops_to_show = remaining_shops.first(3)
      
      Rails.logger.info "===== 今回表示する店舗 ====="
      shops_to_show.each_with_index do |shop, i|
        Rails.logger.info "#{i+1}. #{shop['name']}"
      end
      Rails.logger.info "=================================="
      
      # 表示した店を記録
      shops_to_show.each do |shop|
        @@shown_shops[session_id] << shop.dig('urls', 'pc')
      end
      
      # GPTを使わず、直接フォーマットして返す
      response_text += "ご希望の条件に合うお店を#{shops_to_show.length}件ご紹介します！\n\n"
      
      shops_to_show.each_with_index do |shop, i|
        response_text += "【#{i + 1}. #{shop['name']}】\n"
        response_text += "- ジャンル: #{shop.dig('genre', 'name')}\n"
        response_text += "- 予算: #{shop.dig('budget', 'name')}\n"
        response_text += "- アクセス: #{shop['access']}\n"
        response_text += "- 飲み放題: #{shop['free_drink']}\n" if shop['free_drink'].present?
        response_text += "- コース: #{shop['course']}\n" if shop['course'].present?
        response_text += "- URL: #{shop.dig('urls', 'pc')}\n"
        response_text += "\n"
      end
      
      if remaining_shops.length > 3
        response_text += "（他に#{remaining_shops.length - 3}件の候補があります。「他には？」と聞いてください）"
      end
      
      @@conversations[session_id] << { role: 'assistant', content: response_text }
      render json: { response: response_text }
    else
      # 検索結果がない場合はGPTで通常会話
      chatgpt = ChatgptService.new
      gpt_response = chatgpt.chat(@@conversations[session_id])
      @@conversations[session_id] << { role: 'assistant', content: gpt_response }
      render json: { response: gpt_response }
    end
    
  rescue => e
    Rails.logger.error "Chat Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { response: "エラーが発生しました: #{e.message}" }, status: 500
  end
end

  def reset
    session_id = session.id.to_s
    @@conversations[session_id] = []
    redirect_to chat_path
  end

  private

def should_search?(message)
  # 明らかに不要な会話
  ignore_patterns = [
    /^ありがとう/, /^わかった/, /^了解/, /^なるほど/,
    /^はい$/, /^いいえ$/, /^うん$/
  ]
  
  return false if ignore_patterns.any? { |pattern| message.match?(pattern) }
  
  # 駅名、金額、ジャンル、検索意図のいずれかがあれば検索
  station_pattern = /\w+駅/
  price_pattern = /\d+円/
  search_keywords = [
    /探/, /検索/, /見つけて/, /教えて/, /おすすめ/, /他/, /候補/,
    /イタリアン/, /和食/, /居酒屋/, /串/, /焼肉/, /寿司/
  ]
  
  message.match?(station_pattern) ||
  message.match?(price_pattern) ||
  search_keywords.any? { |pattern| message.match?(pattern) }
end

  def extract_search_params(message)
    # 簡易的な抽出（後で改善可能）
    {
      budget: 'B003',    # 3001〜4000円
      keyword: '居酒屋',
      lat: 35.6895,      # 新宿の緯度
      lng: 139.7004,     # 新宿の経度
      range: 3
    }
  end
end