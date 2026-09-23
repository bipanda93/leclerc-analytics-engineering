import random
from datetime import date, timedelta
from faker import Faker
import pandas as pd
from snowflake.connector.pandas_tools import write_pandas
from ingestion.snowflake_utils import get_connection, SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA



# ── BLOC 1 : EXTRACTION + CATÉGORISATION (OPEN FOOD FACTS) ─────────────────
OFF_QUERY = """
WITH categorized AS (
    SELECT
        code,
        product_name,
        brands,
        CASE
            WHEN categories_tags ILIKE '%en:eggs%' THEN 'Œufs'
            WHEN categories_tags ILIKE '%en:dietary-supplements%' THEN 'Compléments alimentaires'
            WHEN categories_tags ILIKE '%en:coffees%' THEN 'Café'
            WHEN categories_tags ILIKE '%en:cheeses%' THEN 'Fromages'
            WHEN categories_tags ILIKE '%en:dairies%' THEN 'Produits laitiers'
            WHEN categories_tags ILIKE '%en:pickles%' THEN 'Pickles'
            WHEN categories_tags ILIKE '%en:canned-foods%' OR categories_tags ILIKE '%en:foies-gras%' THEN 'Conserves'
            WHEN categories_tags ILIKE '%en:seafood%' THEN 'Poissons'
            WHEN categories_tags ILIKE '%en:biscuits%' THEN 'Biscuits'
            WHEN categories_tags ILIKE '%en:cocoa-and-its-products%' THEN 'Chocolat/cacao'
            WHEN categories_tags ILIKE '%en:confectioneries%' THEN 'Confiseries'
            WHEN categories_tags ILIKE '%en:frozen-foods%' THEN 'Surgelés'
            WHEN categories_tags ILIKE '%en:compotes%' THEN 'Compotes'
            WHEN categories_tags ILIKE '%en:seeds%' THEN 'Graines'
            WHEN categories_tags ILIKE '%en:salty-snacks%' OR categories_tags ILIKE '%en:nuts-and-their-products%' OR categories_tags ILIKE '%en:nuts%' THEN 'Snacks salés'
            WHEN categories_tags ILIKE '%en:fruits-and-vegetables-based-foods%' THEN 'Fruits & légumes'
            WHEN categories_tags ILIKE '%en:fats%' THEN 'Huiles/matières grasses'
            WHEN categories_tags ILIKE '%en:vinegars%' THEN 'Vinaigres'
            WHEN categories_tags ILIKE '%en:desserts%' THEN 'Desserts'
            WHEN categories_tags ILIKE '%en:sandwiches%' THEN 'Sandwiches'
            WHEN categories_tags ILIKE '%en:sweet-snacks%' THEN 'Snacks sucrés'
            WHEN categories_tags ILIKE '%en:sauces%' THEN 'Sauces'
            WHEN categories_tags ILIKE '%en:breads%' THEN 'Pain'
            WHEN categories_tags ILIKE '%en:cereals-and-potatoes%' THEN 'Féculents/pâtes'
            WHEN categories_tags ILIKE '%en:meals%' THEN 'Plats préparés'
            WHEN categories_tags ILIKE '%en:spreads%' THEN 'Pâtes à tartiner'
            WHEN categories_tags ILIKE '%en:meats-and-their-products%' THEN 'Viandes/charcuterie'
            WHEN categories_tags ILIKE '%en:condiments%' OR categories_tags ILIKE '%en:spices%' THEN 'Condiments/Épices'
            WHEN categories_tags ILIKE '%en:beverages%' THEN 'Boissons'
        END AS rayon
    FROM LECLERC.BRONZE.OPENFOODFACTS_PRODUCTS
    WHERE countries_tags ILIKE '%en:france%'
      AND product_name IS NOT NULL
      AND code IS NOT NULL
)
SELECT code, product_name, brands, rayon
FROM categorized
WHERE rayon IS NOT NULL
"""

def fetch_categorized_products(conn):
    with conn.cursor() as cur:
        cur.execute(OFF_QUERY)
        df = cur.fetch_pandas_all()
    return df


# ── BLOC 3 : POIDS PAR RAYON + SAISONNALITÉ + AFFINITÉ ──────────────────────
RAYON_WEIGHTS = {
    "Viandes/charcuterie": 19.50,
    "Fruits & légumes": 13.31,
    "Fromages": 6.43,
    "Plats préparés": 6.35,
    "Boissons": 6.10,
    "Poissons": 5.50,
    "Produits laitiers": 4.94,
    "Pâtes à tartiner": 4.04,
    "Féculents/pâtes": 3.89,
    "Surgelés": 2.62,
    "Sauces": 2.56,
    "Pain": 2.06,
    "Biscuits": 2.03,
    "Compotes": 1.69,
    "Conserves": 2.36,
    "Huiles/matières grasses": 1.05,
    "Condiments/Épices": 1.03,
    "Chocolat/cacao": 1.02,
    "Snacks salés": 0.98,
    "Compléments alimentaires": 0.97,
    "Confiseries": 0.83,
    "Sandwiches": 0.65,
    "Œufs": 0.63,
    "Café": 0.56,
    "Graines": 0.47,
    "Pickles": 0.46,
    "Vinaigres": 0.29,
    "Desserts": 0.12,
}

# index 0 = janvier ... index 11 = décembre
SEASONALITY = {
    "Surgelés":            [0.7, 0.7, 0.8, 0.9, 1.1, 1.4, 1.6, 1.5, 1.0, 0.8, 0.7, 0.8],
    "Boissons":            [0.9, 0.85, 0.9, 1.0, 1.1, 1.3, 1.5, 1.5, 1.0, 0.85, 0.85, 1.15],
    "Chocolat/cacao":      [0.9, 1.1, 1.2, 1.15, 0.85, 0.75, 0.7, 0.75, 0.85, 0.95, 1.2, 1.6],
    "Confiseries":         [0.85, 1.05, 1.0, 1.15, 0.85, 0.8, 0.75, 0.8, 0.85, 1.3, 1.1, 1.5],
    "Plats préparés":      [1.3, 1.25, 1.15, 1.0, 0.9, 0.8, 0.7, 0.7, 0.9, 1.1, 1.25, 1.3],
    "Viandes/charcuterie": [0.9, 0.85, 0.9, 1.0, 1.15, 1.35, 1.4, 1.35, 1.0, 0.85, 0.9, 1.3],
    "Sandwiches":          [0.7, 0.7, 0.8, 0.95, 1.1, 1.3, 1.6, 1.55, 0.95, 0.75, 0.7, 0.75],
}

def seasonal_multiplier(rayon: str, month: int) -> float:
    """month attendu de 1 (janvier) à 12 (décembre)."""
    return SEASONALITY.get(rayon, [1.0] * 12)[month - 1]

AFFINITY_RULES = [
    {"trigger": ["pâtes", "spaghetti", "penne", "tagliatelle"], "boost": ["sauce tomate", "sauce bolognaise"], "probability": 0.6},
    {"trigger": ["café"], "boost": ["sucre", "biscuit"], "probability": 0.6},
    {"trigger": ["chips", "cacahuète", "apéritif"], "boost": ["bière", "soda", "jus"], "probability": 0.6},
    {"trigger": ["pain", "baguette"], "boost": ["confiture", "beurre", "fromage"], "probability": 0.5},
    {"trigger": ["merguez", "saucisse", "steak haché", "brochette"], "boost": ["ketchup", "moutarde", "sauce barbecue"], "probability": 0.6},
    {"trigger": ["sucre en carreaux", "sucre morceaux", "sucre en morceaux"], "boost": ["café", "thé", "chocolat"], "probability": 0.9},
]


# ── BLOC 4 : GÉNÉRATION DES CLIENTS ─────────────────────────────────────────
N_CUSTOMERS = 10000  # ← test à petite échelle ; remettre à 10000 une fois validé
PERIOD_END = date.today()
PERIOD_START = PERIOD_END - timedelta(days=365)

CUSTOMER_PROFILES = {
    "fréquent": {"share": 0.10, "n_transactions_range": (40, 120), "recency_bias": "recent"},
    "régulier": {"share": 0.60, "n_transactions_range": (8, 20), "recency_bias": "spread"},
    "rare":     {"share": 0.30, "n_transactions_range": (1, 4),   "recency_bias": "early"},
}

def generate_customers(n_customers: int = N_CUSTOMERS) -> list[dict]:
    profiles = list(CUSTOMER_PROFILES.keys())
    weights = [CUSTOMER_PROFILES[p]["share"] for p in profiles]
    customers = []
    for _ in range(n_customers):
        profile = random.choices(profiles, weights=weights, k=1)[0]
        low, high = CUSTOMER_PROFILES[profile]["n_transactions_range"]
        customers.append({
            "customer_id": fake.uuid4(),
            "profile": profile,
            "n_transactions": random.randint(low, high),
            "recency_bias": CUSTOMER_PROFILES[profile]["recency_bias"],
        })
    return customers

def random_transaction_date(bias: str) -> date:
    """Tire une date dans la période de 12 mois, biaisée selon le profil.
    'recent' pousse vers la fin de la période, 'early' vers le début,
    'spread' reste uniforme."""
    total_days = (PERIOD_END - PERIOD_START).days
    r = random.random()
    if bias == "recent":
        r = r ** 0.4
    elif bias == "early":
        r = r ** 2.5
    day_offset = int(total_days * r)
    return PERIOD_START + timedelta(days=day_offset)


# ── BLOC 5 : INDEX PRODUITS + GÉNÉRATION D'UN PANIER ────────────────────────
def build_indexes(df):
    """products_by_rayon et products_by_keyword renvoient tous deux des triplets
    (code, nom, rayon) — le rayon voyage avec chaque produit jusqu'au bout."""
    products_by_rayon = {}
    for rayon, group in df.groupby("RAYON"):
        products_by_rayon[rayon] = list(zip(group["CODE"], group["PRODUCT_NAME"], [rayon] * len(group)))

    all_boost_keywords = {kw for rule in AFFINITY_RULES for kw in rule["boost"]}
    lower_names = df["PRODUCT_NAME"].str.lower()
    products_by_keyword = {}
    for kw in all_boost_keywords:
        mask = lower_names.str.contains(kw, na=False)
        subset = df.loc[mask]
        products_by_keyword[kw] = list(zip(subset["CODE"], subset["PRODUCT_NAME"], subset["RAYON"]))

    return products_by_rayon, products_by_keyword

def pick_boosted_product(basket_names: list[str], products_by_keyword: dict):
    """Parcourt les règles d'affinité déclenchées par le panier actuel, et pour
    chacune tente le tirage selon SA PROPRE probabilité — pas une valeur globale.
    Renvoie le premier produit obtenu (ou None si aucune règle n'a 'pris')."""
    for rule in AFFINITY_RULES:
        triggered = any(
            any(kw in name.lower() for kw in rule["trigger"])
            for name in basket_names
        )
        if not triggered:
            continue
        if random.random() < rule["probability"]:
            candidates = [p for kw in rule["boost"] for p in products_by_keyword.get(kw, [])]
            if candidates:
                return random.choice(candidates)
    return None

def pick_basket_size() -> int:
    """La plupart des paniers sont modestes, quelques-uns sont gros —
    loi triangulaire : min 1, max 20, mode (valeur la plus fréquente) 6."""
    return int(random.triangular(1, 20, 6))

def generate_basket(month: int, products_by_rayon: dict, products_by_keyword: dict) -> list[tuple]:
    basket_size = pick_basket_size()
    basket, basket_names = [], []
    rayons = list(RAYON_WEIGHTS.keys())

    for _ in range(basket_size):
        product = pick_boosted_product(basket_names, products_by_keyword)

        if product is None:
            weights = [RAYON_WEIGHTS[r] * seasonal_multiplier(r, month) for r in rayons]
            chosen_rayon = random.choices(rayons, weights=weights, k=1)[0]
            pool = products_by_rayon.get(chosen_rayon)
            if pool:
                product = random.choice(pool)

        if product:
            basket.append(product)
            basket_names.append(product[1])

    return basket


# ── BLOC 6 : QUANTITÉS ───────────────────────────────────────────────────────
QUANTITY_RANGES = {
    "Boissons": (1, 6),
    "Conserves": (1, 5),
}
DEFAULT_QUANTITY_RANGE = (1, 3)

def pick_quantity(rayon: str) -> int:
    low, high = QUANTITY_RANGES.get(rayon, DEFAULT_QUANTITY_RANGE)
    return random.randint(low, high)


# ── BLOC 6 (suite) : PRIX ────────────────────────────────────────────────────
PRICE_QUERY = """
SELECT product_code, AVG(price) AS avg_price
FROM LECLERC.BRONZE.OPEN_PRICES
WHERE currency = 'EUR' AND price IS NOT NULL
GROUP BY product_code
"""

def fetch_real_prices(conn) -> dict:
    with conn.cursor() as cur:
        cur.execute(PRICE_QUERY)
        price_df = cur.fetch_pandas_all()
    return dict(zip(price_df["PRODUCT_CODE"], price_df["AVG_PRICE"]))

KEYWORD_PRICE_OVERRIDES = [
    (["champagne", "crémant"], (15.0, 55.0)),
    (["vin rouge", "vin blanc", "vin rosé", "bordeaux", "bourgogne", "beaujolais", "côtes-du-rhône", "côtes du rhône"], (3.0, 25.0)),
]

PRICE_RANGES = {
    "Viandes/charcuterie": (3.0, 25.0), "Poissons": (4.0, 20.0),
    "Fromages": (2.0, 15.0), "Produits laitiers": (0.5, 5.0),
    "Boissons": (0.5, 5.0),  # eau, soda, jus, bière — vin/champagne traités à part ci-dessus
    "Café": (3.0, 12.0),
    "Fruits & légumes": (0.5, 6.0), "Compotes": (1.0, 4.0),
    "Pain": (0.8, 4.0), "Féculents/pâtes": (0.5, 4.0),
    "Pâtes à tartiner": (1.5, 6.0), "Plats préparés": (2.0, 8.0),
    "Sandwiches": (2.0, 6.0), "Surgelés": (1.5, 10.0),
    "Sauces": (0.8, 5.0), "Conserves": (0.5, 6.0),
    "Pickles": (1.0, 4.0), "Biscuits": (1.0, 5.0),
    "Chocolat/cacao": (1.0, 8.0), "Confiseries": (0.5, 4.0),
    "Snacks salés": (0.8, 4.0), "Snacks sucrés": (0.8, 4.0),
    "Desserts": (1.0, 5.0), "Huiles/matières grasses": (1.5, 10.0),
    "Vinaigres": (1.0, 5.0), "Graines": (1.0, 6.0),
    "Condiments/Épices": (0.5, 5.0), "Compléments alimentaires": (3.0, 20.0),
    "Œufs": (1.5, 4.0),
}

def pick_price(product_code: str, product_name: str, rayon: str, real_prices: dict) -> float:
    if product_code in real_prices:
        return round(float(real_prices[product_code]), 2)

    name_lower = product_name.lower()
    for keywords, (low, high) in KEYWORD_PRICE_OVERRIDES:
        if any(kw in name_lower for kw in keywords):
            return round(random.uniform(low, high), 2)

    low, high = PRICE_RANGES.get(rayon, (1.0, 5.0))
    return round(random.uniform(low, high), 2)


# ── ASSEMBLAGE : CLIENTS + PANIERS → LIGNES DE TRANSACTION ──────────────────
def generate_transactions(customers: list[dict], products_by_rayon: dict, products_by_keyword: dict, real_prices: dict) -> list[dict]:
    rows = []
    transaction_counter = 0

    for customer in customers:
        for _ in range(customer["n_transactions"]):
            transaction_counter += 1
            transaction_id = f"TXN{transaction_counter:08d}"
            txn_date = random_transaction_date(customer["recency_bias"])
            basket = generate_basket(txn_date.month, products_by_rayon, products_by_keyword)

            for code, name, rayon in basket:
                qty = pick_quantity(rayon)
                unit_price = pick_price(code, name, rayon, real_prices)
                rows.append({
                    "transaction_id": transaction_id,
                    "customer_id": customer["customer_id"],
                    "transaction_date": txn_date.isoformat(),
                    "product_code": code,
                    "product_name": name,
                    "quantity": qty,
                    "unit_price": unit_price,
                    "line_total": round(qty * unit_price, 2),
                })

    return rows


# ── BLOC 7 : ÉCRITURE VERS BRONZE ────────────────────────────────────────────
TRANSACTIONS_TABLE = "TRANSACTIONS"

def create_transactions_table(conn):
    with conn.cursor() as cur:
        cur.execute(f"""
            CREATE OR REPLACE TABLE {SNOWFLAKE_DATABASE}.{SNOWFLAKE_SCHEMA}.{TRANSACTIONS_TABLE} (
                transaction_id VARCHAR,
                customer_id VARCHAR,
                transaction_date DATE,
                product_code VARCHAR,
                product_name VARCHAR,
                quantity NUMBER,
                unit_price FLOAT,
                line_total FLOAT
            )
        """)

def safe_code_to_str(value):
    """Convertit un code produit (potentiellement float, NaN, ou invalide) en
    chaîne d'entier propre — renvoie None si la conversion est impossible,
    plutôt que de faire planter tout le run sur une seule valeur corrompue."""
    try:
        if pd.isna(value):
            return None
        return str(int(round(float(value))))
    except (ValueError, OverflowError, TypeError):
        return None

def write_transactions_to_bronze(conn, rows: list[dict]):
    df = pd.DataFrame(rows)
    before = len(df)
    df["product_code"] = df["product_code"].apply(safe_code_to_str)
    df = df.dropna(subset=["product_code"])
    dropped = before - len(df)
    if dropped:
        print(f"{dropped} ligne(s) écartée(s) — product_code invalide")
    df.columns = [c.upper() for c in df.columns]
    success, nchunks, nrows, _ = write_pandas(
        conn,
        df,
        table_name=TRANSACTIONS_TABLE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_SCHEMA,
    )
    return success, nrows


# ── ORCHESTRATION ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    with get_connection() as conn:
        print("Récupération des produits catégorisés...")
        products_df = fetch_categorized_products(conn)
        print(f"{len(products_df)} produits récupérés")

        print("Récupération des prix réels (Open Prices)...")
        real_prices = fetch_real_prices(conn)
        print(f"{len(real_prices)} prix réels disponibles")

        print("Construction des index produits...")
        products_by_rayon, products_by_keyword = build_indexes(products_df)

        print(f"Génération de {N_CUSTOMERS} clients...")
        customers = generate_customers()

        print("Génération des transactions...")
        rows = generate_transactions(customers, products_by_rayon, products_by_keyword, real_prices)
        print(f"{len(rows)} lignes de transaction générées")

        print("Création de la table cible...")
        create_transactions_table(conn)

        print("Écriture vers Bronze...")
        success, nrows = write_transactions_to_bronze(conn, rows)
        print(f"Écriture {'réussie' if success else 'échouée'} — {nrows} lignes chargées")