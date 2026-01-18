Rails.application.routes.draw do
  # ルートパス（トップページ）をチャット画面に設定
  root 'chat#index'
  
  get 'chat', to: 'chat#index'
  post 'chat', to: 'chat#create'
  post 'chat/reset', to: 'chat#reset'
  
  # その他のルート
end