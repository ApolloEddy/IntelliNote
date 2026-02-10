# 笔记/文档类型分类及其对应的 Emoji 映射表

NOTEBOOK_TAXONOMY = {
    # 学术与教育
    "mathematics": "📐",    # 数学/几何
    "physics": "⚛️",        # 物理/量子
    "chemistry": "🧪",      # 化学
    "biology": "🧬",        # 生物/基因
    "history": "🏺",        # 历史/考古
    "literature": "📚",     # 文学/阅读
    "language_learning": "🗣️", # 语言学习
    "research_paper": "🎓",  # 论文/学术研究

    # 技术与开发
    "software_development": "💻", # 编程/开发
    "data_science": "📊",    # 数据科学
    "artificial_intelligence": "🤖", # AI/ML
    "cybersecurity": "🛡️",   # 网络安全
    "devops": "🏗️",         # 运维/架构

    # 商业与职业
    "finance": "💰",        # 财务/金融
    "marketing": "📢",      # 市场/营销
    "management": "👔",     # 管理/领导力
    "legal": "⚖️",          # 法律/合同
    "meeting_minutes": "📝", # 会议纪要
    "resume_cv": "📄",       # 简历/求职

    # 生活与个人
    "travel_planning": "✈️", # 旅行计划
    "cooking_recipes": "🍳", # 烹饪/食谱
    "health_fitness": "💪",  # 健身/健康
    "journal_diary": "📔",   # 日记/随笔
    "music_art": "🎨",       # 艺术/音乐
    "gaming": "🎮",          # 游戏/攻略
    "shopping_list": "🛒",   # 购物清单
    
    # 其他
    "general": "📁",        # 通用
    "unknown": "❓",        # 未知
}

# 用于 Prompt 的分类列表字符串
TAXONOMY_LIST_STR = ", ".join([key for key in NOTEBOOK_TAXONOMY.keys() if key not in ["general", "unknown"]])
