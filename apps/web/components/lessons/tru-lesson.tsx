'use client';

import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { motion, AnimatePresence, useInView } from '@/components/motion';
import {
  Minimize2,
  Terminal,
  Zap,
  FileCode,
  BarChart3,
  Settings,
  Play,
  Shield,
  ArrowRight,
  RotateCcw,
  ChevronLeft,
  ChevronRight,
  Gauge,
  Sparkles,
  Code2,
  Database,
  Braces,
  Component,
} from 'lucide-react';
import {
  Section,
  Paragraph,
  CodeBlock,
  TipBox,
  Highlight,
  Divider,
  GoalBanner,
  CommandList,
  FeatureCard,
  FeatureGrid,
} from './lesson-components';

function InteractiveTokenCompressor() {
  return <InteractiveTokenCompressorImpl />;
}

export function TruLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Compress source code into token-optimized notation so more context fits in each LLM request.
      </GoalBanner>

      {/* Section 1: What Is TRU */}
      <Section title="What Is TRU?" icon={<Minimize2 className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          <Highlight>TRU (toon_rust)</Highlight> converts source code into a compact,
          token-optimized notation that preserves semantic meaning while dramatically
          reducing token count. Feed more code context into LLMs without hitting limits.
        </Paragraph>
        <Paragraph>
          When working with large codebases, context windows fill up fast. TRU
          compresses code by 40-70% in token count while keeping it understandable
          to LLMs, letting you include more files in each request.
        </Paragraph>

        <div className="mt-8">
          <FeatureGrid>
            <FeatureCard
              icon={<Minimize2 className="h-5 w-5" />}
              title="40-70% Smaller"
              description="Dramatic token reduction"
              gradient="from-blue-500/20 to-indigo-500/20"
            />
            <FeatureCard
              icon={<FileCode className="h-5 w-5" />}
              title="Multi-Language"
              description="Rust, Python, TypeScript, Go"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<BarChart3 className="h-5 w-5" />}
              title="Token Counting"
              description="Before/after comparisons"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Zap className="h-5 w-5" />}
              title="Rust Speed"
              description="Processes large repos instantly"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <div className="mt-8">
        <InteractiveTokenCompressor />
      </div>

      <Divider />

      {/* Section 2: Quick Start */}
      <Section title="Quick Start" icon={<Play className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Convert a file or directory to token-optimized notation.
        </Paragraph>

        <CodeBlock
          code={`# Convert a single file
toon compress src/main.rs

# Convert an entire directory
toon compress src/

# See token savings
toon compress --stats src/main.rs
# Before: 2,847 tokens → After: 1,139 tokens (60% reduction)`}
          filename="Basic Usage"
        />

        <TipBox variant="tip">
          Use <code>--stats</code> to see exactly how many tokens you saved.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 3: Commands */}
      <Section title="Essential Commands" icon={<Terminal className="h-5 w-5" />} delay={0.2}>
        <CommandList
          commands={[
            { command: 'toon compress <file>', description: 'Compress a file to token-optimized format' },
            { command: 'toon compress --stats <file>', description: 'Compress with token count comparison' },
            { command: 'toon decompress <file>', description: 'Restore from compressed notation' },
            { command: 'toon --help', description: 'Show all available options' },
          ]}
        />
      </Section>

      <Divider />

      {/* Section 4: How It Works */}
      <Section title="How It Works" icon={<Settings className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          TRU applies language-aware transformations that LLMs can still understand.
        </Paragraph>

        <CodeBlock
          code={`# Original (high token count):
pub fn calculate_fibonacci(n: u64) -> u64 {
    if n <= 1 {
        return n;
    }
    let mut a: u64 = 0;
    let mut b: u64 = 1;
    for _ in 2..=n {
        let temp = a + b;
        a = b;
        b = temp;
    }
    b
}

# TRU compressed (lower token count):
fn fib(n:u64)->u64{if n<=1{ret n}
let(mut a,mut b)=(0u64,1u64);
for _ in 2..=n{let t=a+b;a=b;b=t}b}`}
          filename="Compression Example"
        />

        <TipBox variant="info">
          The compressed output is still valid, readable code. LLMs understand it
          perfectly since they process tokens, not visual formatting.
        </TipBox>
      </Section>

      <Divider />

      {/* Section 5: Integration */}
      <Section title="Flywheel Integration" icon={<Shield className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          Combine TRU with other flywheel tools for maximum context efficiency.
        </Paragraph>

        <div className="grid gap-3 sm:grid-cols-2">
          <div className="p-3 rounded-lg bg-emerald-500/10 border border-emerald-500/30">
            <span className="text-emerald-400 font-semibold">TRU + S2P</span>
            <p className="text-white/80 text-sm mt-1">Generate prompts, then compress for more context</p>
          </div>
          <div className="p-3 rounded-lg bg-blue-500/10 border border-blue-500/30">
            <span className="text-blue-400 font-semibold">TRU + FSFS</span>
            <p className="text-white/80 text-sm mt-1">Search results compressed for LLM consumption</p>
          </div>
          <div className="p-3 rounded-lg bg-violet-500/10 border border-violet-500/30">
            <span className="text-violet-400 font-semibold">TRU + PCR</span>
            <p className="text-white/80 text-sm mt-1">Post-compaction reminders with compressed context</p>
          </div>
          <div className="p-3 rounded-lg bg-amber-500/10 border border-amber-500/30">
            <span className="text-amber-400 font-semibold">TRU + CASR</span>
            <p className="text-white/80 text-sm mt-1">Cross-agent session context stays within limits</p>
          </div>
        </div>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Interactive Token Compression Laboratory
// ---------------------------------------------------------------------------

interface CodeSample {
  id: string;
  lang: string;
  label: string;
  icon: React.ReactNode;
  original: string;
  compressed: string;
  originalTokens: number;
  compressedTokens: number;
  color: string;
  gradient: string;
}

const CODE_SAMPLES: CodeSample[] = [
  {
    id: 'typescript-class',
    lang: 'TypeScript',
    label: 'TypeScript Class',
    icon: <Braces className="h-3.5 w-3.5" />,
    color: 'text-blue-400',
    gradient: 'from-blue-500/20 to-cyan-500/20',
    original: `export class UserRepository {
  private readonly db: Database;
  private readonly cache: CacheService;

  constructor(database: Database, cacheService: CacheService) {
    this.db = database;
    this.cache = cacheService;
  }

  async findById(userId: string): Promise<User | null> {
    const cached = await this.cache.get(\`user:\${userId}\`);
    if (cached !== null) {
      return JSON.parse(cached) as User;
    }
    const user = await this.db.query<User>(
      'SELECT * FROM users WHERE id = $1',
      [userId],
    );
    if (user !== null) {
      await this.cache.set(
        \`user:\${userId}\`,
        JSON.stringify(user),
        3600,
      );
    }
    return user;
  }

  async updateProfile(
    userId: string,
    updates: Partial<UserProfile>,
  ): Promise<User> {
    const user = await this.db.query<User>(
      'UPDATE users SET profile = profile || $2 WHERE id = $1 RETURNING *',
      [userId, JSON.stringify(updates)],
    );
    await this.cache.del(\`user:\${userId}\`);
    return user;
  }
}`,
    compressed: `export class UserRepo{
private db:DB;private cache:Cache
constructor(db:DB,cache:Cache){this.db=db;this.cache=cache}
async findById(id:str):Promise<User|null>{
const c=await this.cache.get(\`user:\${id}\`)
if(c!==null)ret JSON.parse(c) as User
const u=await this.db.query<User>(
'SELECT * FROM users WHERE id=$1',[id])
if(u!==null)await this.cache.set(\`user:\${id}\`,JSON.stringify(u),3600)
ret u}
async updateProfile(id:str,upd:Partial<Profile>):Promise<User>{
const u=await this.db.query<User>(
'UPDATE users SET profile=profile||$2 WHERE id=$1 RETURNING *',
[id,JSON.stringify(upd)])
await this.cache.del(\`user:\${id}\`)
ret u}}`,
    originalTokens: 248,
    compressedTokens: 132,
  },
  {
    id: 'java-interface',
    lang: 'Java',
    label: 'Java Interface',
    icon: <Code2 className="h-3.5 w-3.5" />,
    color: 'text-orange-400',
    gradient: 'from-orange-500/20 to-red-500/20',
    original: `public interface PaymentGateway {
  /**
   * Process a payment transaction.
   * @param amount The payment amount in cents
   * @param currency The ISO 4217 currency code
   * @param customerId The unique customer identifier
   * @return PaymentResult with transaction details
   * @throws PaymentException if processing fails
   */
  PaymentResult processPayment(
    long amount,
    String currency,
    String customerId
  ) throws PaymentException;

  /**
   * Refund a previously completed transaction.
   * @param transactionId The original transaction ID
   * @param amount Refund amount (partial or full)
   * @return RefundResult with refund details
   */
  RefundResult refundTransaction(
    String transactionId,
    long amount
  ) throws PaymentException;

  /**
   * Check the status of a transaction.
   */
  TransactionStatus getTransactionStatus(
    String transactionId
  );

  default boolean isRefundable(TransactionStatus status) {
    return status == TransactionStatus.COMPLETED
        || status == TransactionStatus.PARTIALLY_REFUNDED;
  }
}`,
    compressed: `interface PaymentGW{
//Process payment txn
PaymentResult processPayment(long amt,String cur,String custId)throws PayEx;
//Refund completed txn
RefundResult refundTxn(String txnId,long amt)throws PayEx;
//Check txn status
TxnStatus getTxnStatus(String txnId);
default bool isRefundable(TxnStatus s){
ret s==TxnStatus.COMPLETED||s==TxnStatus.PARTIALLY_REFUNDED;}}`,
    originalTokens: 196,
    compressedTokens: 78,
  },
  {
    id: 'python-module',
    lang: 'Python',
    label: 'Python Module',
    icon: <FileCode className="h-3.5 w-3.5" />,
    color: 'text-yellow-400',
    gradient: 'from-yellow-500/20 to-green-500/20',
    original: `from dataclasses import dataclass, field
from typing import Optional, List
from datetime import datetime

@dataclass
class TaskResult:
    """Result of a completed task execution."""
    task_id: str
    status: str
    output: Optional[str] = None
    errors: List[str] = field(default_factory=list)
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None

    @property
    def duration_seconds(self) -> Optional[float]:
        """Calculate task duration in seconds."""
        if self.started_at and self.completed_at:
            delta = self.completed_at - self.started_at
            return delta.total_seconds()
        return None

    @property
    def is_successful(self) -> bool:
        """Check if task completed without errors."""
        return self.status == "completed" and len(self.errors) == 0

    def to_summary(self) -> dict:
        """Generate a summary dictionary."""
        return {
            "task_id": self.task_id,
            "status": self.status,
            "duration": self.duration_seconds,
            "error_count": len(self.errors),
        }`,
    compressed: `@dataclass
class TaskResult:
task_id:str;status:str
output:str|None=None
errors:list[str]=field(default_factory=list)
started_at:datetime|None=None
completed_at:datetime|None=None
@property
def duration_s(self)->float|None:
if self.started_at and self.completed_at:
ret(self.completed_at-self.started_at).total_seconds()
ret None
@property
def is_ok(self)->bool:ret self.status=="completed"and len(self.errors)==0
def to_summary(self)->dict:ret{"task_id":self.task_id,
"status":self.status,"duration":self.duration_s,
"error_count":len(self.errors)}`,
    originalTokens: 218,
    compressedTokens: 108,
  },
  {
    id: 'go-struct',
    lang: 'Go',
    label: 'Go Struct',
    icon: <Settings className="h-3.5 w-3.5" />,
    color: 'text-cyan-400',
    gradient: 'from-cyan-500/20 to-blue-500/20',
    original: `type ServerConfig struct {
	Host         string        \`json:"host"\`
	Port         int           \`json:"port"\`
	ReadTimeout  time.Duration \`json:"read_timeout"\`
	WriteTimeout time.Duration \`json:"write_timeout"\`
	MaxBodySize  int64         \`json:"max_body_size"\`
	TLSEnabled   bool          \`json:"tls_enabled"\`
	CertFile     string        \`json:"cert_file,omitempty"\`
	KeyFile      string        \`json:"key_file,omitempty"\`
}

func NewServerConfig() *ServerConfig {
	return &ServerConfig{
		Host:         "0.0.0.0",
		Port:         8080,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		MaxBodySize:  10 << 20, // 10 MB
		TLSEnabled:   false,
	}
}

func (c *ServerConfig) Validate() error {
	if c.Port < 1 || c.Port > 65535 {
		return fmt.Errorf("invalid port: %d", c.Port)
	}
	if c.TLSEnabled {
		if c.CertFile == "" || c.KeyFile == "" {
			return fmt.Errorf("TLS requires cert and key files")
		}
	}
	return nil
}

func (c *ServerConfig) Address() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}`,
    compressed: `type SrvCfg struct{
Host str;Port int;ReadTO,WriteTO time.Duration
MaxBody int64;TLS bool;Cert,Key str}
func NewSrvCfg()*SrvCfg{ret&SrvCfg{
Host:"0.0.0.0",Port:8080,
ReadTO:30*time.Second,WriteTO:30*time.Second,
MaxBody:10<<20,TLS:false}}
func(c*SrvCfg)Validate()err{
if c.Port<1||c.Port>65535{ret errorf("bad port:%d",c.Port)}
if c.TLS{if c.Cert==""||c.Key==""{
ret errorf("TLS needs cert+key")}}
ret nil}
func(c*SrvCfg)Addr()str{ret sprintf("%s:%d",c.Host,c.Port)}`,
    originalTokens: 231,
    compressedTokens: 106,
  },
  {
    id: 'react-component',
    lang: 'React',
    label: 'React Component',
    icon: <Component className="h-3.5 w-3.5" />,
    color: 'text-violet-400',
    gradient: 'from-violet-500/20 to-purple-500/20',
    original: `export function DataTable<T extends Record<string, unknown>>({
  data,
  columns,
  sortable = true,
  onRowClick,
  emptyMessage = "No data available",
}: DataTableProps<T>) {
  const [sortColumn, setSortColumn] = useState<string | null>(null);
  const [sortDirection, setSortDirection] = useState<"asc" | "desc">("asc");
  const [currentPage, setCurrentPage] = useState(0);
  const pageSize = 25;

  const sortedData = useMemo(() => {
    if (!sortColumn) return data;
    return [...data].sort((a, b) => {
      const aVal = a[sortColumn];
      const bVal = b[sortColumn];
      const comparison = String(aVal).localeCompare(String(bVal));
      return sortDirection === "asc" ? comparison : -comparison;
    });
  }, [data, sortColumn, sortDirection]);

  const pageData = useMemo(
    () => sortedData.slice(
      currentPage * pageSize,
      (currentPage + 1) * pageSize,
    ),
    [sortedData, currentPage],
  );

  const totalPages = Math.ceil(data.length / pageSize);

  if (data.length === 0) {
    return (
      <div className="text-center py-12 text-gray-500">
        {emptyMessage}
      </div>
    );
  }

  return (
    <div className="overflow-x-auto rounded-lg border">
      <table className="w-full text-sm">
        <thead className="bg-gray-50">
          {columns.map((col) => (
            <th
              key={col.key}
              onClick={() => {
                if (!sortable) return;
                setSortDirection(
                  sortColumn === col.key && sortDirection === "asc"
                    ? "desc" : "asc"
                );
                setSortColumn(col.key);
              }}
              className="px-4 py-3 text-left font-medium"
            >
              {col.label}
            </th>
          ))}
        </thead>
        <tbody>
          {pageData.map((row, i) => (
            <tr
              key={i}
              onClick={() => onRowClick?.(row)}
              className="border-t hover:bg-gray-50 cursor-pointer"
            >
              {columns.map((col) => (
                <td key={col.key} className="px-4 py-3">
                  {String(row[col.key] ?? "")}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}`,
    compressed: `export fn DataTable<T extends Record<str,unknown>>({
data,columns,sortable=true,onRowClick,emptyMsg="No data"}:Props<T>){
const[sCol,setSCol]=useState<str|null>(null)
const[sDir,setSDir]=useState<"asc"|"desc">("asc")
const[pg,setPg]=useState(0);const pSz=25
const sorted=useMemo(()=>{if(!sCol)ret data
ret[...data].sort((a,b)=>{
const c=String(a[sCol]).localeCompare(String(b[sCol]))
ret sDir==="asc"?c:-c})},[data,sCol,sDir])
const pgData=useMemo(
()=>sorted.slice(pg*pSz,(pg+1)*pSz),[sorted,pg])
const totPg=Math.ceil(data.length/pSz)
if(!data.length)ret<div cn="text-center py-12 text-gray-500">{emptyMsg}</div>
ret<div cn="overflow-x-auto rounded-lg border">
<table cn="w-full text-sm"><thead cn="bg-gray-50">
{columns.map(c=><th key={c.key}
onClick={()=>{if(!sortable)ret
setSDir(sCol===c.key&&sDir==="asc"?"desc":"asc")
setSCol(c.key)}} cn="px-4 py-3 text-left font-medium">{c.label}</th>)}
</thead><tbody>
{pgData.map((r,i)=><tr key={i}onClick={()=>onRowClick?.(r)}
cn="border-t hover:bg-gray-50 cursor-pointer">
{columns.map(c=><td key={c.key}cn="px-4 py-3">
{String(r[c.key]??"")}</td>)}</tr>)}</tbody></table></div>}`,
    originalTokens: 382,
    compressedTokens: 198,
  },
  {
    id: 'sql-query',
    lang: 'SQL',
    label: 'SQL Query',
    icon: <Database className="h-3.5 w-3.5" />,
    color: 'text-emerald-400',
    gradient: 'from-emerald-500/20 to-teal-500/20',
    original: `-- Get top customers with their order statistics
-- for the current quarter, including running totals
SELECT
    customers.customer_id,
    customers.full_name,
    customers.email_address,
    COUNT(DISTINCT orders.order_id) AS total_orders,
    SUM(order_items.quantity * order_items.unit_price) AS total_revenue,
    AVG(order_items.quantity * order_items.unit_price) AS avg_order_value,
    MAX(orders.created_at) AS last_order_date,
    SUM(SUM(order_items.quantity * order_items.unit_price))
        OVER (ORDER BY customers.customer_id) AS running_total
FROM customers
INNER JOIN orders
    ON orders.customer_id = customers.customer_id
INNER JOIN order_items
    ON order_items.order_id = orders.order_id
WHERE orders.created_at >= DATE_TRUNC('quarter', CURRENT_DATE)
    AND orders.status NOT IN ('cancelled', 'refunded')
GROUP BY
    customers.customer_id,
    customers.full_name,
    customers.email_address
HAVING SUM(order_items.quantity * order_items.unit_price) > 1000
ORDER BY total_revenue DESC
LIMIT 50;`,
    compressed: `--Top customers w/ order stats, current quarter, running totals
SELECT c.customer_id,c.full_name,c.email_address,
COUNT(DISTINCT o.order_id)total_orders,
SUM(oi.quantity*oi.unit_price)total_rev,
AVG(oi.quantity*oi.unit_price)avg_val,
MAX(o.created_at)last_order,
SUM(SUM(oi.quantity*oi.unit_price))OVER(ORDER BY c.customer_id)running_total
FROM customers c
JOIN orders o ON o.customer_id=c.customer_id
JOIN order_items oi ON oi.order_id=o.order_id
WHERE o.created_at>=DATE_TRUNC('quarter',CURRENT_DATE)
AND o.status NOT IN('cancelled','refunded')
GROUP BY c.customer_id,c.full_name,c.email_address
HAVING SUM(oi.quantity*oi.unit_price)>1000
ORDER BY total_rev DESC LIMIT 50;`,
    originalTokens: 205,
    compressedTokens: 118,
  },
];

// ---------------------------------------------------------------------------
// Animated token counter display
// ---------------------------------------------------------------------------
function AnimatedCounter({
  value,
  duration = 1.2,
  className,
}: {
  value: number;
  duration?: number;
  className?: string;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const from = prevRef.current;
    const to = value;
    prevRef.current = value;
    if (from === to) return;

    const start = performance.now();
    const ms = duration * 1000;

    function tick(now: number) {
      const elapsed = now - start;
      const progress = Math.min(elapsed / ms, 1);
      // Ease-out cubic
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(from + (to - from) * eased);
      setDisplay(current);
      if (progress < 1) {
        rafRef.current = requestAnimationFrame(tick);
      }
    }

    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
  }, [value, duration]);

  return <span className={className}>{display.toLocaleString()}</span>;
}

// ---------------------------------------------------------------------------
// Compression gauge / dial
// ---------------------------------------------------------------------------
function CompressionGauge({
  percentage,
  isActive,
}: {
  percentage: number;
  isActive: boolean;
}) {
  const radius = 52;
  const stroke = 8;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (percentage / 100) * circumference;

  return (
    <div className="relative flex items-center justify-center">
      <svg width="130" height="130" viewBox="0 0 130 130" className="-rotate-90">
        {/* Background arc */}
        <circle
          cx="65"
          cy="65"
          r={radius}
          fill="none"
          stroke="rgba(255,255,255,0.06)"
          strokeWidth={stroke}
          strokeLinecap="round"
        />
        {/* Active arc */}
        <motion.circle
          cx="65"
          cy="65"
          r={radius}
          fill="none"
          stroke="url(#gaugeGradient)"
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circumference}
          initial={{ strokeDashoffset: circumference }}
          animate={{
            strokeDashoffset: isActive ? offset : circumference,
          }}
          transition={{ type: 'spring', stiffness: 40, damping: 15, delay: 0.3 }}
        />
        <defs>
          <linearGradient id="gaugeGradient" x1="0%" y1="0%" x2="100%" y2="0%">
            <stop offset="0%" stopColor="#34d399" />
            <stop offset="50%" stopColor="#22d3ee" />
            <stop offset="100%" stopColor="#818cf8" />
          </linearGradient>
        </defs>
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <AnimatePresence mode="wait">
          {isActive ? (
            <motion.div
              key="active"
              initial={{ opacity: 0, scale: 0.5 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.5 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="text-center"
            >
              <span className="text-2xl font-bold font-mono text-emerald-400">
                {percentage}%
              </span>
              <p className="text-[10px] text-white/40 uppercase tracking-wider mt-0.5">
                reduced
              </p>
            </motion.div>
          ) : (
            <motion.div
              key="idle"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="text-center"
            >
              <Gauge className="h-6 w-6 text-white/20 mx-auto" />
              <p className="text-[10px] text-white/30 mt-1">Ratio</p>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Context window savings bar
// ---------------------------------------------------------------------------
function ContextWindowBar({
  originalTokens,
  savedTokens,
  isActive,
}: {
  originalTokens: number;
  savedTokens: number;
  isActive: boolean;
}) {
  const contextWindowSize = 128000;
  const recoveredPct = (savedTokens / contextWindowSize) * 100;
  const usedPct = (originalTokens / contextWindowSize) * 100;

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-[10px]">
        <span className="text-white/50 uppercase tracking-wider font-semibold">
          128k Context Window
        </span>
        <AnimatePresence mode="wait">
          {isActive && (
            <motion.span
              initial={{ opacity: 0, x: 10 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: 10 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="text-emerald-400 font-mono"
            >
              +{savedTokens.toLocaleString()} tokens recovered
            </motion.span>
          )}
        </AnimatePresence>
      </div>
      <div className="relative h-6 rounded-full bg-white/[0.04] border border-white/[0.06] overflow-hidden">
        {/* Used portion */}
        <motion.div
          className="absolute inset-y-0 left-0 rounded-full bg-white/[0.08]"
          initial={{ width: `${usedPct}%` }}
          animate={{ width: `${usedPct}%` }}
        />
        {/* Recovered portion - glowing */}
        <AnimatePresence>
          {isActive && (
            <motion.div
              className="absolute inset-y-0 rounded-full"
              style={{ left: `${usedPct - recoveredPct}%` }}
              initial={{ width: 0, opacity: 0 }}
              animate={{ width: `${recoveredPct}%`, opacity: 1 }}
              exit={{ width: 0, opacity: 0 }}
              transition={{ type: 'spring', stiffness: 60, damping: 18, delay: 0.5 }}
            >
              <div className="h-full rounded-full bg-gradient-to-r from-emerald-500/40 to-cyan-500/40 shadow-[0_0_20px_rgba(52,211,153,0.3)]" />
            </motion.div>
          )}
        </AnimatePresence>
        {/* Scale marks */}
        <div className="absolute inset-0 flex items-center justify-between px-1">
          {[0, 25, 50, 75, 100].map((mark) => (
            <div key={mark} className="w-px h-2 bg-white/[0.08]" />
          ))}
        </div>
      </div>
      <div className="flex justify-between text-[10px] text-white/30 font-mono">
        <span>0</span>
        <span>32k</span>
        <span>64k</span>
        <span>96k</span>
        <span>128k</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Particle burst effect
// ---------------------------------------------------------------------------
function ParticleBurst({ isActive }: { isActive: boolean }) {
  const [particles] = useState(() =>
    Array.from({ length: 12 }, (_, i) => ({
      id: i,
      angle: (i / 12) * 360,
      distance: 30 + ((i * 7 + 3) % 11) * 4,
      size: 2 + ((i * 3 + 1) % 5) * 0.6,
      delay: ((i * 5 + 2) % 12) * 0.025,
      duration: 0.6 + ((i * 4 + 1) % 10) * 0.04,
    })),
  );

  return (
    <AnimatePresence>
      {isActive &&
        particles.map((p) => {
          const rad = (p.angle * Math.PI) / 180;
          const x = Math.cos(rad) * p.distance;
          const y = Math.sin(rad) * p.distance;
          return (
            <motion.div
              key={p.id}
              className="absolute rounded-full bg-emerald-400"
              style={{
                width: p.size,
                height: p.size,
                left: '50%',
                top: '50%',
              }}
              initial={{ x: 0, y: 0, opacity: 1, scale: 1 }}
              animate={{ x, y, opacity: 0, scale: 0 }}
              exit={{ opacity: 0 }}
              transition={{
                duration: p.duration,
                delay: p.delay,
                ease: 'easeOut',
              }}
            />
          );
        })}
    </AnimatePresence>
  );
}

// ---------------------------------------------------------------------------
// Compression phase indicator
// ---------------------------------------------------------------------------
type CompressionPhase = 'idle' | 'scanning' | 'tokenizing' | 'compressing' | 'optimizing' | 'done';

const PHASE_CONFIG: Record<CompressionPhase, { label: string; color: string }> = {
  idle: { label: 'Ready', color: 'text-white/40' },
  scanning: { label: 'Scanning AST...', color: 'text-blue-400' },
  tokenizing: { label: 'Tokenizing...', color: 'text-cyan-400' },
  compressing: { label: 'Compressing identifiers...', color: 'text-violet-400' },
  optimizing: { label: 'Optimizing output...', color: 'text-amber-400' },
  done: { label: 'Compression complete', color: 'text-emerald-400' },
};

function PhaseIndicator({ phase, active }: { phase: CompressionPhase; active: boolean }) {
  const config = PHASE_CONFIG[phase];
  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={phase}
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -6 }}
        transition={{ type: 'spring', stiffness: 200, damping: 25 }}
        className={`flex items-center gap-2 text-xs font-medium ${config.color}`}
      >
        {phase !== 'idle' && phase !== 'done' && (
          <motion.div
            animate={active ? { rotate: 360 } : { rotate: 0 }}
            transition={active ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
          >
            <Minimize2 className="h-3 w-3" />
          </motion.div>
        )}
        {phase === 'done' && <Sparkles className="h-3 w-3" />}
        <span>{config.label}</span>
      </motion.div>
    </AnimatePresence>
  );
}

// ---------------------------------------------------------------------------
// Token highlight overlay for original code
// ---------------------------------------------------------------------------
function HighlightedCode({
  code,
  phase,
}: {
  code: string;
  phase: CompressionPhase;
}) {
  const lines = code.split('\n');
  const isScanning = phase === 'scanning' || phase === 'tokenizing';
  const isCompressing = phase === 'compressing' || phase === 'optimizing';

  return (
    <pre className="p-4 text-xs font-mono leading-relaxed overflow-x-auto max-h-72 overflow-y-auto">
      {lines.map((line, lineIdx) => (
        <div key={lineIdx} className="relative">
          <motion.span
            animate={{
              color: isCompressing
                ? 'rgba(255,255,255,0.3)'
                : 'rgba(255,255,255,0.7)',
            }}
            transition={{ duration: 0.4 }}
          >
            {line}
          </motion.span>
          {/* Scan line effect */}
          <AnimatePresence>
            {isScanning && (
              <motion.div
                className="absolute inset-0 bg-blue-400/[0.06] rounded"
                initial={{ opacity: 0 }}
                animate={{ opacity: [0, 1, 0] }}
                exit={{ opacity: 0 }}
                transition={{
                  duration: 0.6,
                  delay: lineIdx * 0.05,
                  repeat: 0,
                }}
              />
            )}
          </AnimatePresence>
          {line === '' && '\n'}
        </div>
      ))}
    </pre>
  );
}

// ---------------------------------------------------------------------------
// Main Interactive Token Compressor Implementation
// ---------------------------------------------------------------------------
function InteractiveTokenCompressorImpl() {
  const [selectedSample, setSelectedSample] = useState(0);
  const [phase, setPhase] = useState<CompressionPhase>('idle');
  const [displayedTokens, setDisplayedTokens] = useState(0);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const [showParticles, setShowParticles] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const inView = useInView(rootRef, { amount: 0.15 });

  const sample = CODE_SAMPLES[selectedSample];
  const isCompressed = phase === 'done';
  const isRunning = phase !== 'idle' && phase !== 'done';

  const reductionPct = useMemo(
    () => Math.round((1 - sample.compressedTokens / sample.originalTokens) * 100),
    [sample],
  );

  const savedTokens = useMemo(
    () => sample.originalTokens - sample.compressedTokens,
    [sample],
  );

  const clearTimers = useCallback(() => {
    for (const t of timersRef.current) clearTimeout(t);
    timersRef.current = [];
  }, []);

  const handleCompress = useCallback(() => {
    if (isRunning) return;
    clearTimers();
    setPhase('idle');
    setDisplayedTokens(sample.originalTokens);
    setShowParticles(false);

    // Phase sequence with delays
    const schedule = (fn: () => void, ms: number) => {
      const t = setTimeout(fn, ms);
      timersRef.current.push(t);
    };

    schedule(() => setPhase('scanning'), 50);
    schedule(() => setPhase('tokenizing'), 600);
    schedule(() => {
      setPhase('compressing');
      setDisplayedTokens(Math.round(sample.originalTokens * 0.7));
    }, 1200);
    schedule(() => {
      setPhase('optimizing');
      setDisplayedTokens(Math.round(sample.originalTokens * 0.4));
    }, 1900);
    schedule(() => {
      setPhase('done');
      setDisplayedTokens(sample.compressedTokens);
      setShowParticles(true);
    }, 2500);
    schedule(() => setShowParticles(false), 3500);
  }, [clearTimers, isRunning, sample]);

  const handleReset = useCallback(() => {
    clearTimers();
    setPhase('idle');
    setDisplayedTokens(0);
    setShowParticles(false);
  }, [clearTimers]);

  const handleSelectSample = useCallback(
    (idx: number) => {
      clearTimers();
      setSelectedSample(idx);
      setPhase('idle');
      setDisplayedTokens(0);
      setShowParticles(false);
    },
    [clearTimers],
  );

  const handlePrev = useCallback(() => {
    const next = selectedSample === 0 ? CODE_SAMPLES.length - 1 : selectedSample - 1;
    handleSelectSample(next);
  }, [selectedSample, handleSelectSample]);

  const handleNext = useCallback(() => {
    const next = selectedSample === CODE_SAMPLES.length - 1 ? 0 : selectedSample + 1;
    handleSelectSample(next);
  }, [selectedSample, handleSelectSample]);

  useEffect(() => clearTimers, [clearTimers]);

  return (
    <div ref={rootRef} className="relative rounded-3xl border border-white/[0.08] bg-gradient-to-br from-white/[0.02] to-transparent backdrop-blur-xl overflow-hidden">
      {/* Background glows */}
      <div className="absolute top-0 left-1/4 w-96 h-96 bg-blue-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute bottom-0 right-1/4 w-72 h-72 bg-indigo-500/[0.03] rounded-full blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-64 h-64 bg-emerald-500/[0.02] rounded-full blur-3xl pointer-events-none" />

      <div className="relative p-6 sm:p-8 space-y-6">
        {/* Header */}
        <div className="text-center space-y-2">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-white/[0.08] bg-white/[0.02]">
            <Sparkles className="h-3.5 w-3.5 text-emerald-400" />
            <span className="text-xs font-semibold text-white/70">
              Token Compression Laboratory
            </span>
          </div>
          <p className="text-xs text-white/40 max-w-md mx-auto">
            Select a code sample, run compression, and watch tokens shrink in real time.
            See exactly how much context window you recover.
          </p>
        </div>

        {/* Sample stepper */}
        <div className="flex items-center gap-3 justify-center">
          <motion.button
            type="button"
            onClick={handlePrev}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className="flex items-center justify-center w-8 h-8 rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/80 transition-colors"
          >
            <ChevronLeft className="h-4 w-4" />
          </motion.button>

          <div className="flex flex-wrap justify-center gap-1.5">
            {CODE_SAMPLES.map((s, i) => (
              <motion.button
                key={s.id}
                type="button"
                onClick={() => handleSelectSample(i)}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                className={`flex items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-medium transition-colors ${
                  selectedSample === i
                    ? `border-white/[0.15] bg-white/[0.06] ${s.color}`
                    : 'border-white/[0.06] bg-white/[0.01] text-white/40 hover:text-white/60'
                }`}
              >
                {s.icon}
                <span className="hidden sm:inline">{s.label}</span>
                <span className="sm:hidden">{s.lang}</span>
              </motion.button>
            ))}
          </div>

          <motion.button
            type="button"
            onClick={handleNext}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            className="flex items-center justify-center w-8 h-8 rounded-xl border border-white/[0.08] bg-white/[0.02] text-white/50 hover:text-white/80 transition-colors"
          >
            <ChevronRight className="h-4 w-4" />
          </motion.button>
        </div>

        {/* Sample info bar */}
        <div className="flex items-center justify-between px-2">
          <div className="flex items-center gap-2">
            <div className={`w-2 h-2 rounded-full ${isCompressed ? 'bg-emerald-400' : isRunning ? 'bg-blue-400 animate-pulse' : 'bg-white/20'}`} />
            <span className="text-xs text-white/60 font-medium">{sample.label}</span>
            <span className="text-[10px] text-white/30 font-mono">{sample.lang}</span>
          </div>
          <PhaseIndicator phase={phase} active={inView} />
        </div>

        {/* Split panel: original and compressed */}
        <div className="grid gap-4 lg:grid-cols-2">
          {/* Original code panel */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden">
            <div className="flex items-center justify-between px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.01]">
              <div className="flex items-center gap-2">
                <div className="flex gap-1">
                  <div className="w-2 h-2 rounded-full bg-red-400/50" />
                  <div className="w-2 h-2 rounded-full bg-yellow-400/50" />
                  <div className="w-2 h-2 rounded-full bg-green-400/50" />
                </div>
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Original Source
                </span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[10px] font-mono text-white/40">
                  {sample.originalTokens.toLocaleString()} tokens
                </span>
                <FileCode className="h-3 w-3 text-white/20" />
              </div>
            </div>
            <HighlightedCode code={sample.original} phase={phase} />
          </div>

          {/* Compressed output panel */}
          <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] overflow-hidden relative">
            <div className="flex items-center justify-between px-4 py-2.5 border-b border-white/[0.06] bg-white/[0.01]">
              <div className="flex items-center gap-2">
                <div className="flex gap-1">
                  <div className="w-2 h-2 rounded-full bg-red-400/50" />
                  <div className="w-2 h-2 rounded-full bg-yellow-400/50" />
                  <div className="w-2 h-2 rounded-full bg-green-400/50" />
                </div>
                <span className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  TRU Compressed
                </span>
              </div>
              <AnimatePresence mode="wait">
                {isCompressed && (
                  <motion.div
                    key="token-count-compressed"
                    initial={{ opacity: 0, y: -4 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: 4 }}
                    transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    className="flex items-center gap-2"
                  >
                    <span className="text-[10px] font-mono text-emerald-400">
                      {sample.compressedTokens.toLocaleString()} tokens
                    </span>
                    <Zap className="h-3 w-3 text-emerald-400" />
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
            <div className="relative min-h-[200px]">
              <AnimatePresence mode="wait">
                {isRunning && (
                  <motion.div
                    key="compressing-animation"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="absolute inset-0 flex flex-col items-center justify-center gap-4 p-6"
                  >
                    {/* Pulsing compression icon */}
                    <div className="relative">
                      <motion.div
                        animate={
                          inView
                            ? { scale: [1, 1.3, 1], opacity: [0.3, 0.6, 0.3] }
                            : { scale: 1, opacity: 0.3 }
                        }
                        transition={inView ? { duration: 1.5, repeat: Infinity } : { duration: 0.2 }}
                        className="absolute inset-0 rounded-full bg-blue-500/20 blur-xl"
                        style={{ width: 60, height: 60, left: -10, top: -10 }}
                      />
                      <motion.div
                        animate={inView ? { rotate: 360 } : { rotate: 0 }}
                        transition={inView ? { duration: 2, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                      >
                        <Minimize2 className="h-10 w-10 text-blue-400/80" />
                      </motion.div>
                    </div>
                    {/* Live token counter */}
                    <div className="text-center">
                      <p className="text-[10px] text-white/40 uppercase tracking-wider mb-1">
                        Token Count
                      </p>
                      <AnimatedCounter
                        value={displayedTokens}
                        duration={0.6}
                        className="text-2xl font-bold font-mono text-blue-300"
                      />
                    </div>
                    {/* Progress dots */}
                    <div className="flex gap-1.5">
                      {[0, 1, 2, 3].map((i) => (
                        <motion.div
                          key={i}
                          className="w-1.5 h-1.5 rounded-full bg-blue-400"
                          animate={inView ? { opacity: [0.2, 1, 0.2] } : { opacity: 0.2 }}
                          transition={
                            inView
                              ? { duration: 0.8, repeat: Infinity, delay: i * 0.15 }
                              : { duration: 0.2 }
                          }
                        />
                      ))}
                    </div>
                  </motion.div>
                )}
                {isCompressed && (
                  <motion.pre
                    key="compressed-result"
                    initial={{ opacity: 0, scale: 0.95, y: 10 }}
                    animate={{ opacity: 1, scale: 1, y: 0 }}
                    transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                    className="p-4 text-xs text-emerald-300/80 font-mono leading-relaxed overflow-x-auto max-h-72 overflow-y-auto"
                  >
                    {sample.compressed}
                  </motion.pre>
                )}
                {phase === 'idle' && (
                  <motion.div
                    key="placeholder-idle"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    className="absolute inset-0 flex flex-col items-center justify-center gap-3"
                  >
                    <div className="w-16 h-16 rounded-2xl border border-dashed border-white/[0.1] flex items-center justify-center">
                      <Minimize2 className="h-6 w-6 text-white/15" />
                    </div>
                    <span className="text-xs text-white/25">
                      Click &ldquo;Compress&rdquo; to see the result
                    </span>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>
        </div>

        {/* Stats dashboard - appears after compression */}
        <AnimatePresence>
          {isCompressed && (
            <motion.div
              initial={{ opacity: 0, y: 20, height: 0 }}
              animate={{ opacity: 1, y: 0, height: 'auto' }}
              exit={{ opacity: 0, y: 20, height: 0 }}
              transition={{ type: 'spring', stiffness: 200, damping: 25 }}
              className="space-y-4 overflow-hidden"
            >
              {/* Stats row with gauge */}
              <div className="rounded-2xl border border-emerald-500/20 bg-emerald-500/[0.04] p-5">
                <div className="grid gap-6 sm:grid-cols-[1fr_auto_1fr]">
                  {/* Token comparison */}
                  <div className="flex flex-col items-center justify-center gap-4">
                    <div className="flex items-center gap-4">
                      {/* Before */}
                      <div className="text-center">
                        <p className="text-[10px] text-white/40 uppercase tracking-wider mb-1">Before</p>
                        <motion.div
                          initial={{ scale: 1.2, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                        >
                          <span className="text-xl font-bold font-mono text-white/70">
                            {sample.originalTokens.toLocaleString()}
                          </span>
                        </motion.div>
                        <p className="text-[10px] text-white/30">tokens</p>
                      </div>

                      {/* Arrow */}
                      <motion.div
                        initial={{ scale: 0, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.1 }}
                        className="relative"
                      >
                        <ArrowRight className="h-5 w-5 text-emerald-400/60" />
                        <ParticleBurst isActive={showParticles} />
                      </motion.div>

                      {/* After */}
                      <div className="text-center">
                        <p className="text-[10px] text-white/40 uppercase tracking-wider mb-1">After</p>
                        <motion.div
                          initial={{ scale: 1.2, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.15 }}
                        >
                          <span className="text-xl font-bold font-mono text-emerald-400">
                            {sample.compressedTokens.toLocaleString()}
                          </span>
                        </motion.div>
                        <p className="text-[10px] text-emerald-400/50">tokens</p>
                      </div>
                    </div>

                    {/* Saved tokens badge */}
                    <motion.div
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ type: 'spring', stiffness: 200, damping: 25, delay: 0.25 }}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-emerald-500/10 border border-emerald-500/20"
                    >
                      <Sparkles className="h-3 w-3 text-emerald-400" />
                      <span className="text-xs font-semibold text-emerald-400">
                        {savedTokens.toLocaleString()} tokens saved
                      </span>
                    </motion.div>
                  </div>

                  {/* Gauge */}
                  <div className="flex items-center justify-center">
                    <CompressionGauge percentage={reductionPct} isActive={isCompressed} />
                  </div>

                  {/* Bar chart comparison */}
                  <div className="flex items-center justify-center">
                    <div className="flex items-end gap-3 h-28">
                      {/* Before bar */}
                      <div className="flex flex-col items-center gap-1.5">
                        <span className="text-[10px] font-mono text-white/40">
                          {sample.originalTokens}
                        </span>
                        <motion.div
                          initial={{ height: 0 }}
                          animate={{ height: 80 }}
                          transition={{ type: 'spring', stiffness: 100, damping: 20, delay: 0.1 }}
                          className="w-10 rounded-t-lg bg-gradient-to-t from-white/[0.08] to-white/[0.15]"
                        />
                        <span className="text-[10px] text-white/40 font-medium">Before</span>
                      </div>
                      {/* After bar */}
                      <div className="flex flex-col items-center gap-1.5">
                        <span className="text-[10px] font-mono text-emerald-400/80">
                          {sample.compressedTokens}
                        </span>
                        <motion.div
                          initial={{ height: 80 }}
                          animate={{ height: 80 * (1 - reductionPct / 100) }}
                          transition={{ type: 'spring', stiffness: 100, damping: 20, delay: 0.3 }}
                          className="w-10 rounded-t-lg bg-gradient-to-t from-emerald-500/30 to-emerald-400/50"
                        />
                        <span className="text-[10px] text-emerald-400/60 font-medium">After</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Context window savings bar */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5">
                <ContextWindowBar
                  originalTokens={sample.originalTokens}
                  savedTokens={savedTokens}
                  isActive={isCompressed}
                />
              </div>

              {/* Compression breakdown */}
              <div className="rounded-2xl border border-white/[0.08] bg-white/[0.02] p-5 space-y-3">
                <p className="text-[10px] font-semibold text-white/50 uppercase tracking-wider">
                  Compression Techniques Applied
                </p>
                <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  {[
                    { label: 'Identifier shortening', pct: '25%', color: 'bg-blue-400' },
                    { label: 'Whitespace removal', pct: '30%', color: 'bg-violet-400' },
                    { label: 'Comment stripping', pct: '20%', color: 'bg-amber-400' },
                    { label: 'Syntax optimization', pct: '25%', color: 'bg-emerald-400' },
                  ].map((technique, i) => (
                    <motion.div
                      key={technique.label}
                      initial={{ opacity: 0, x: -10 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{
                        type: 'spring',
                        stiffness: 200,
                        damping: 25,
                        delay: 0.1 * i,
                      }}
                      className="flex items-center gap-2 p-2 rounded-lg bg-white/[0.02]"
                    >
                      <div className={`w-1.5 h-6 rounded-full ${technique.color}/40`} />
                      <div className="flex-1 min-w-0">
                        <p className="text-[10px] text-white/60 truncate">{technique.label}</p>
                        <p className="text-xs font-bold font-mono text-white/80">{technique.pct}</p>
                      </div>
                    </motion.div>
                  ))}
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {/* Controls */}
        <div className="flex items-center justify-center gap-3">
          <motion.button
            type="button"
            onClick={handleCompress}
            whileHover={{ scale: 1.04 }}
            whileTap={{ scale: 0.96 }}
            transition={{ type: 'spring', stiffness: 200, damping: 25 }}
            disabled={isRunning}
            className={`flex items-center gap-2 rounded-2xl border px-6 py-2.5 text-sm font-medium transition-colors ${
              isRunning
                ? 'border-white/[0.06] bg-white/[0.02] text-white/30 cursor-wait'
                : 'border-blue-500/30 bg-blue-500/10 text-blue-300 hover:bg-blue-500/20'
            }`}
          >
            {isRunning ? (
              <>
                <motion.div
                  animate={inView ? { rotate: 360 } : { rotate: 0 }}
                  transition={inView ? { duration: 1, repeat: Infinity, ease: 'linear' } : { duration: 0.2 }}
                >
                  <Minimize2 className="h-4 w-4" />
                </motion.div>
                Compressing...
              </>
            ) : (
              <>
                <Zap className="h-4 w-4" />
                {isCompressed ? 'Re-Compress' : 'Compress'}
              </>
            )}
          </motion.button>

          <AnimatePresence>
            {isCompressed && (
              <motion.button
                type="button"
                onClick={handleReset}
                initial={{ opacity: 0, scale: 0.8 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.8 }}
                transition={{ type: 'spring', stiffness: 200, damping: 25 }}
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.96 }}
                className="flex items-center gap-2 rounded-2xl border border-white/[0.08] bg-white/[0.02] px-5 py-2.5 text-sm font-medium text-white/50 hover:text-white/70 transition-colors"
              >
                <RotateCcw className="h-4 w-4" />
                Reset
              </motion.button>
            )}
          </AnimatePresence>
        </div>

        {/* Step counter */}
        <div className="flex items-center justify-center gap-1.5">
          {CODE_SAMPLES.map((_, i) => (
            <button
              key={i}
              type="button"
              onClick={() => handleSelectSample(i)}
              className={`w-1.5 h-1.5 rounded-full transition-colors ${
                i === selectedSample ? 'bg-white/60' : 'bg-white/15 hover:bg-white/25'
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
