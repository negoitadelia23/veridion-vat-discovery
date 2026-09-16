## Repository Structure 

README.md - contains the written assignment

master/vat_id_test.R - the R script containing the Proof of Concept

Part 1: Research. What did you learn that wasn’t obvious at the start? Which sources exist, which are usable, what did you rule out and why? Show the trail, not only the conclusion. For the paths that mattered I want the evidence: what you ran, what came back, the number you got. A claim I can trace to something you actually did counts for more than one I cannot. Write up the dead ends too, and be specific: for each one that mattered, name the source, what you expected, and the exact reason it failed. “Scraping is unreliable” is not a dead end; “this source returns VAT numbers but only for a small share of my sample, and here is the evidence” is. The search matters as much as what you found.
To begin with, I accessed the official Companies House database (Basic Company Data). I downloaded the “Part 1 of 7” file from the bulk dataset to see what data was available. Next, I checked the database schema, available at: https://resources.companieshouse.gov.uk/toolsToHelp/pdf/freeDataProductDataset.pdf. Here, the first problem arises (which is also mentioned in the project requirements): there is no column for the VAT Registration Number (or even a “Website URL”). Thus, I cannot use the dataset as a direct source for VAT information.
I realized that the dataset can be used as:
1.	A starting point (Reference List): useful for extracting a clean sample of companies to search for (by filtering out inactive or foreign companies);
2.	A trusted source for identity validation (also known as Entity Resolution): When I find a VAT number and validate it via the HMRC API, it will return the name and address. This way, I ensure that the number belongs exactly to the company I’m looking for and avoid false matches.

Although the dataset from Companies House provided me with the names of the companies I needed to search for, I first wanted to test if my web scraping script actually works. To create a “Ground Truth” (a reference dataset against which I can evaluate my results), I identified the public procurement data from the government sector (Public Sector Spend Data from data.gov.uk). Unlike Companies House, these files directly link the supplier’s name to the VAT registration number. Although this source has a “selection bias” (it covers only companies that have contracts with the government), it provides me with a perfect real-world sample for testing and measuring accuracy (FPR/FNR),

Before querying the government database, I established a mandatory pre-validation step. Knowing that UK VAT numbers use a checksum algorithm (Modulus 97), I will implement this function locally. Any number extracted (from a CSV file or via web scraping) will first be run through the Modulus 97 algorithm. If it is mathematically invalid, it is instantly rejected, thus avoiding unnecessary resource consumption and the risk of hitting the official API’s rate limits.

In addition to the classic Modulus 97 algorithm, I took into account that HMRC had introduced the Modulus 9755 scheme. A robust implementation tests both variants (adding 55 before the sequence of subtractions); otherwise, the local filter would reject valid numbers from recent generations as invalid, generating hidden false negatives before the HMRC verification.

I also investigated how the discovered numbers will be validated via the HMRC API (a mandatory requirement of the project). I identified the “Check a UK VAT number” API on the official HMRC developer portal. This allows me to automate (and thus streamline) the verification of the discovered numbers and extract the names and official addresses in JSON format, facilitating the entity resolution process with the Companies House database.

Dead End 1:

•	What did I test:
I found sales data dumps (e.g., a file on Payhip containing ~1 million companies and VAT codes for a ridiculously low price).  

•	What did I expect:
To quickly fill a large portion of that gap of 2/3 missing companies, thereby solving the problem.

•	Why did I exclude this approach:
I realized that purchased data becomes outdated very quickly. Having access to a preview version of a Payhip dataset, I tested a few numbers on the HMRC website and found expired codes belonging to dissolved companies. Since entering an incorrect VAT number into the client’s system would skew the analysis, I preferred to learn how to extract official data, even if it’s more technically challenging. I wouldn’t rely on a list from a source without a clear update mechanism or a list from an untrustworthy third party.

Dead End 2:

•	What did I test:
I created an R script that searches for company names and extracts strings using the regular expression (?:GB)?\s*\d{9}. I took a sample of 10 companies 

•	What was I expecting:
I expected that validating a VAT number would be a simple GET request. In reality, I discovered that the HMRC API is severely restricted. Their “Sandbox” environment returns a 404 Not Found error for any real company (since it is completely isolated from the production registry). To validate real data, I was forced to request production tokens, which introduced strict compliance barriers (GDPR policies, security audit: 10 business days!). Simple HTTP queries performed in R frequently run into protection mechanisms (Cookie Consent screens, WAFs) or return pages with no useful content due to the lack of JavaScript execution, making data extraction impossible without a headless approach.

•	What were the results:
Massive noise. The results included ZIP codes, phone numbers, or Company Registration Numbers (CRN), which for England and Wales are exactly 8 alphanumeric characters long (and for Scotland/Northern Ireland use prefixes such as SC or NI).
All in all, a simple web search is a dead end without a strict mathematical filter, thus justifying my pre-validation step using Modulus 97.

Dead End 2b:

•	What did I test:
I ran the same scraping process in R, but introduced a human-like delay using Sys.sleep(sample(2:4, 1)). I used a different dataset, “Spending over £500,” published by Bristol City Council, and increased the sample size to n=35 to verify the robustness and scalability of the process.

•	What did I expect:
I expected to be able to obtain the HTML source code of the search engine’s results pages, so that I could subsequently apply the regex filter and the Modulus 97 algorithm to the extracted candidates.

•	The reason it failed:
The failure rate was 100%: for all 35 attempts, the search engine returned either a 403 (Forbidden) status or Cookie Consent pages that did not contain the search results.
Introducing a 2–4-second delay did not resolve the issue. This indicates that the block was not caused solely by an excessive volume of requests or simple rate limiting. Instead, automated access via HTTP requests from R failed to retrieve the actual content of the results, suggesting the existence of additional protection mechanisms and/or the need to execute JavaScript.
Here, I learned the hard way that simple HTTP requests (the ones I was familiar with) are no longer sufficient for today’s web.

Part 2: Build something that works, on a sample you choose. Tell us how you drew the sample and why it’s representative; a sample of companies you already knew published their VAT number will produce an impressive number and teach neither of us anything. Every number you report as found must be confirmed against HMRC’s checker: state the false-positive rate you measured, how you measured it, and on what sample. Numbers you did not verify do not count. Report what your process achieved and what your numbers don’t capture.

I divided the proof of concept into two phases to test both the extraction logic and scalability. (Note: The complete R script supporting this process can be found in the repository under master/vat_id_test.R).

Phase 1: Validation of the logic and false-positive rate

I extracted an initial sample of n=10 companies to run the entire pipeline locally.

•	How I measured: Any string extracted from the web was run through my Modulus 97 verification function. The numbers that passed the mathematical validation were then verified using the HMRC checker to establish the ground truth and validate the entity association.

•	Results: 
The pipeline extracted 3 codes that passed the Modulus 97 validation.

•	HMRC Confirmation: Of these 3 mathematically valid codes, 2 were officially confirmed by HMRC as belonging to the companies being searched for, and 1 was refuted (a mathematically valid number, but one that belonged to another entity or was inactive);

•	False-Positive Rate: Low statistical power (n=3): with only 3 mathematically valid candidates in the sample, an FPR of 33.3% is a very fragile estimate, with such a small sample, adding or removing just one company would change the figure by tens of percentage points. The sample demonstrates the concept (valid checksum ≠ correct entity), but does not support a reliable error rate;

•	Match Rate / Coverage: Of all 10 companies in the sample, the script was able to extract and confirm through HMRC a correct VAT number for 2 companies resulting in a coverage rate of 20% (2/10). This figure is distinct from the false positive rate: FPR measures how often a candidate that passes the local checksum is incorrect, while coverage measures what percentage of the target population (the companies being searched for) the pipeline successfully covers from start to finish. Low coverage (20%) indicates that, although the accuracy for the candidates found is reasonable, the main bottleneck in the current process is in the extraction phase (7 out of 10 companies did not produce any valid candidates in the first phase), not in the validation phase.

•	!! Limits of this variant:

1.	Low statistical power (n=3): With only 3 mathematically valid candidates in the sample, the FPR of 33.3% is an estimate.
2.	Structural selection bias: The sample extracted from public spending data has a much cleaner and more official digital footprint than the long tail of Companies House records. Therefore, the success rate from this sample cannot be directly generalized to the general population.

Phase 2: Scalability Test

I increased the sample size to n = 35 to test the robustness and scalability of the process. Here I encountered the limitation documented in the “Dead Ends” section: a 100% failure rate in extraction due to browser fingerprinting measures on search engines.
The script was no longer able to retrieve the HTML needed to apply the regex, returning only NA values.

Since my current script processes only raw HTML text obtained through a standard HTTP request, it completely misses VAT numbers that are:

•	Embedded in images (e.g., scanned invoices) or PDF files uploaded to company websites;

•	Hidden in B2B portals that require authentication (login walls);

•	Rendered strictly through JavaScript frameworks (Single Page Applications) where the initial source code delivered via HTTP is empty.

Part 3: What you’d do with real resources. You’re on a personal laptop with no budget. We aren’t. Given a cluster, a crawling budget, commercial data sources, proxy infrastructure, an annotation team — whatever the problem actually needs — how would coverage and accuracy change, and how would you get there? Be specific enough that I can argue with you: rough cost per company, what breaks first, what you’d monitor in production. “I’d use a distributed crawler” tells us nothing.
If I had access to an enterprise-grade infrastructure, a crawling budget, and commercial proxies, the approach would shift from sequential local extraction to a scalable and robust data engineering pipeline:

•	Crawling Infrastructure: To overcome the failure documented in Dead End 2/2b, I would move the logic from R to a language like Python and use “headless browser” tools (e.g., Playwright). These can render JavaScript and bypass cookie banners, running everything on a cloud server with rotating IP addresses;

•	Monitoring and Preventing Data Decay: To avoid selling expired data to the client (the issue in Dead End 1), I would implement a Continuous Verification system. Each stored VAT number would have a last_verified_date field. Monthly, an automated job would re-query the HMRC API for a percentage of the database, monitoring the company deregistration rate;

•	Teamwork: The manual validation team is too slow to search for numbers from scratch. I would use them only for exceptions: for example, when a name found on the web is similar but not exactly identical to the one returned by HMRC, and the script isn’t sure if it’s the same company;
•	Production Monitoring Metrics:

  o	Match Rate & Coverage: The percentage of Companies House firms for which we find a VAT number validated by HMRC;

  o	Infra Health: The rate of HTTP 429 / 5xx errors on the HMRC API and the ban rate for proxies on search engines;

  o	Data Drift / Quality Alert: An automatic alert triggered by any unusual spike in the false-positive rate measured on continuous validation batches (crucial for preventing client data corruption).
  
Debate Topic and Strategic Considerations

•	UK VAT numbers consist of nine digits plus a checksum, so only a small fraction of the possible combinations are valid. What happens if you apply that observation to HMRC’s checker, and is it a good idea?

If we apply this observation, that only a small fraction of 9-digit combinations satisfy the checksum for a VAT registration number, it follows that the HMRC API should not be used as the first filter for codes collected from the internet.

Here’s what would happen: if we sent every 9-digit string extracted from websites to HMRC, we would generate a large volume of requests for values that can be filtered out locally before any external verification. This would result in unnecessary traffic and latency and would quickly push us toward the API’s usage limits. HMRC currently specifies a standard limit of 3 requests per second per application, according to the HMRC Dev Hub Reference Guide, and exceeding this limit results in HTTP 429 Too Many Requests responses. It’s not a good idea to actually use the HMRC as a brute filter for all 9-digit combinations, however, yes, it’d be very useful to first perform local validation of the format and checksum and send only the candidates that pass the filter to HMRC.

However, a local checksum does not mean that the number is necessarily active or that it belongs to a specific company. HMRC notes that the mathematical verification can confirm compliance with the format, but cannot confirm the current existence of the registration or the identity of the holder.

Systematically generating all numbers that pass the checksum, followed by querying HMRC to determine which ones exist, is a much more problematic approach. It would turn the API into an enumeration/brute-force mechanism and would contradict the purpose of the service’s traffic limits and responsible use policies.

Thus, the checksum is used as a pre-validation filter, and HMRC remains the source for the actual verification of the registration.

•	How would you keep this dataset up to date, given that companies register and deregister continuously?

I would use a hybrid system: I would monitor the free monthly updates from Companies House to directly flag companies that are deregistered, and for the rest, I would run an automatic background recheck (via the HMRC API), processing a small portion of the database each day.

•	How would you know your dataset was wrong at scale, with nothing complete to compare it against?

When operating without a complete absolute reference, data accuracy and data drift are inferred through signal proxies, cross-validation, and automated anomaly detection:

•	Alerts for inconsistencies between sources: We monitor logical overlaps. If Companies House lists a company as “Active,” but automated validation shows that its VAT number has suddenly been invalidated or deregistered with HMRC, the discrepancy triggers a top-priority alert;

•	Human-in-the-Loop Audits: We continuously extract a small, random sample from the newly processed records (e.g., 50–100 per week) for secondary verification or manual audit. If the false-positive rate measured on this micro-sample exceeds the agreed tolerance threshold (e.g., >2%), a circuit breaker is triggered, blocking data ingestion and forcing a technical investigation.

•	Which of your sources would you not be comfortable using in a product we sell, and why?

I would never use static data dumps from third parties or unofficial listings acquired without a clear provenance (such as databases containing millions of companies sold cheaply on unregulated platforms), due to the following factors:

•	Risk (Data Decay and Liability): In B2B data engineering, an incorrect number costs considerably more than a missing number. Unregulated third-party sources suffer from a massive rate of data decay: they frequently contain defunct companies or reassigned numbers and offer no SLA or update history.

•	Business Impact: If a client uses our data for procurement or tax compliance, and a corrupted VAT number obtained from a dubious source results in an incorrect tax invoice or a fine from the authorities, the legal and reputational risk falls entirely on our company. Any record in a commercial product requires a strict chain of custody: either official government records or web extracts verified directly through the government’s API.

Beyond the UK:

Germany is an excellent case study for international scaling because it completely reverses the difficulty dynamics compared to the UK.

•	Discovery becomes trivial (predictable web scraping): Under Germany’s Telemediengesetz (TMG), companies conducting online business are required to maintain an “Impressum” page, which must include their VAT number (USt-IdNr), if one has been assigned. Thus, the effort involved in web scraping ceases to be a blind search through search engines. It becomes predictable, targeted (we search directly for the /impressum path on a known domain), and much less computationally intensive;

•	Verification becomes a bottleneck (Compliance Bottleneck): Unlike HMRC (UK), the German government imposes strict confidentiality rules. Their official system (Bundeszentralamt für Steuern - eVatR) requires what is called a Qualified Request. The first mandatory parameter in the API is the “Eigene USt-IdNr” (the requester’s own German VAT ID);

•	Strategic conclusion: While the challenge in the UK is technical, in Germany and other European countries, the issue becomes a severe compliance barrier. My data extraction pipeline would easily adapt to the German market, but the process would stall at the official verification stage. Building this product for Germany requires a locally registered tax presence (or a partnership with a valid German entity) to legitimize the queries.

I looked through the official European API (VIES) documentation to see if I could simplify my work by using a single system. But I quickly realized the impact of Brexit: VIES no longer validates the classic GB prefixes for British companies. The only exception is Northern Ireland (prefix XI), which has remained in the system for trade with the EU. Therefore, to build a complete and accurate dataset for our client (who has suppliers throughout the United Kingdom), connecting to HMRC is absolutely mandatory and cannot be replaced by VIES.
