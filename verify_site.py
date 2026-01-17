import asyncio
from playwright.async_api import async_playwright

async def verify():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        )
        page = await context.new_page()
        
        print("[INFO] Navigating to TCDD site...")
        try:
            # wait_until='domcontentloaded' is faster and more reliable
            await page.goto("https://ebilet.tcddtasimacilik.gov.tr", wait_until="domcontentloaded", timeout=30000)
            print(f"[SUCCESS] Title: {await page.title()}")
            
            # Check for key selectors
            selectors = {
                "Nereden Input": "#fromTrainInput",
                "Nereye Input": "#toTrainInput",
                "Sefer Ara Button": "#searchSeferButton"
            }
            
            for name, sel in selectors.items():
                el = await page.query_selector(sel)
                if el:
                    print(f"[SUCCESS] {name} found!")
                else:
                    print(f"[FAILED] {name} NOT found!")
                    
        except Exception as e:
            print(f"[ERROR] Verification failed: {e}")
        finally:
            await browser.close()

if __name__ == "__main__":
    asyncio.run(verify())
