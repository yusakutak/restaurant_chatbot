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
    # ジャンルキーワード
    genre_keywords = {
      /お好み焼き|お好み/ => 'お好み焼き',
      /焼肉/ => '焼肉',
      /イタリアン|パスタ|ピザ/ => 'イタリアン',
      /ラーメン/ => 'ラーメン',
      /寿司|握り寿司|回転寿司/ => '寿司',
      /和食/ => '和食',
      /居酒屋/ => '居酒屋',
      /カレー/ => 'カレー',
      /中華|チャイナ/ => '中華',
      /フレンチ|フランス料理/ => 'フレンチ',
      /串|串焼き/ => '串焼き',
      /鶏/ => '鶏料理',
      /魚/ => '魚',
      /肉/ => '肉'
    }
    
    keyword = '居酒屋'  # デフォルト
    genre_keywords.each do |pattern, name|
      if message.match?(pattern)
        keyword = name
        break
      end
    end
    
    # 予算の抽出
    budget_code = 'B003'  # デフォルト 3001～4000円
    if message.match?(/1000|千円|～?1000/)
      budget_code = 'B001'  # ～1000円
    elsif message.match?(/2000|2,000|～?2000/)
      budget_code = 'B002'  # 1001～2000円
    elsif message.match?(/3000|3,000|～?3000/)
      budget_code = 'B003'  # 2001～3000円
    elsif message.match?(/4000|4,000|～?4000/)
      budget_code = 'B004'  # 3001～4000円
    elsif message.match?(/5000|5,000|～?5000/)
      budget_code = 'B005'  # 4001～5000円
    elsif message.match?(/安|お手頃|リーズナブル/)
      budget_code = 'B001'  # ～1000円
    elsif message.match?(/高級|贅沢/)
      budget_code = 'B005'  # 4001～5000円
    end
    
    # 場所・駅名の抽出
    stations = {
      /新宿/ => { lat: 35.6895, lng: 139.7004 },
      /渋谷/ => { lat: 35.6595, lng: 139.7004 },
      /池袋/ => { lat: 35.7295, lng: 139.7108 },
      /銀座/ => { lat: 35.6764, lng: 139.7727 },
      /赤坂/ => { lat: 35.6764, lng: 139.7329 },
      /六本木/ => { lat: 35.6627, lng: 139.7308 },
      /表参道/ => { lat: 35.6653, lng: 139.7157 },
      /青山/ => { lat: 35.6725, lng: 139.7266 },
      /飯田橋/ => { lat: 35.7047, lng: 139.7432 },
      /四ツ谷/ => { lat: 35.6850, lng: 139.7381 },
      /赤坂見附/ => { lat: 35.6765, lng: 139.7348 },
      /麻布十番/ => { lat: 35.6480, lng: 139.7360 },
      /恵比寿/ => { lat: 35.6456, lng: 139.7297 }
    }
    
    # デフォルト座標（新宿）
    location = { lat: 35.6895, lng: 139.7004 }
    
    stations.each do |pattern, coords|
      if message.match?(pattern)
        location = coords
        break
      end
    end
    
    {
      budget: budget_code,
      keyword: keyword,
      lat: location[:lat],
      lng: location[:lng],
      range: 3
    }
  end
end