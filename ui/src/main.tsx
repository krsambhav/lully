import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Theme, Button, IconButton, TextField, TextArea, Select, Switch, Slider, Popover, Tooltip, Tabs, SegmentedControl } from '@radix-ui/themes';
import { ArrowUp, ArrowLeft, Mic, Volume2, AudioLines, Check, ChevronRight, Copy, EyeOff, Keyboard, LoaderCircle, Minus, Monitor, Pin, PinOff, ScanLine, Settings2, Sun, Moon, ShieldCheck, Sparkles, Square, X, Zap, RotateCcw, CircleHelp, SlidersHorizontal, KeyRound } from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import '@radix-ui/themes/styles.css';
import '@fontsource-variable/plus-jakarta-sans/wght.css';
import './style.css';

type Turn = {id:string;question:string;answer:string;pending:boolean;issue:string;firstToken:number|null};
type Snapshot = {
  opacity:number; focusRequest:number; chatSession:string; bundledKey:boolean; captureProtection:boolean; theme: 'light'|'dark'|'system'; screenAccess:boolean; turns:Turn[]; recordingShortcut: 'hide'|'pin'|'capture'|null;
  native: boolean; provider: string; model: string; endpoint: string; keySaved: boolean; deep: boolean; pinned: boolean;
  answer: string; screen: string; transcript: string; error: string; listening: boolean; audioBusy: boolean;
  reading: boolean; thinking: boolean; settings: boolean; systemAudio: boolean; autoAssist: boolean;
  firstToken: number | null; screenTime: string | null; hideShortcut: string; pinShortcut: string; captureShortcut:string; prompt?:string;
};
type Command = { action: string; [key: string]: unknown };
declare global { interface Window { webkit?: { messageHandlers: { lully: { postMessage: (data: Command) => void } } }; lullyReceive?: (data: Snapshot) => void } }
const initial: Snapshot = {opacity:1,focusRequest:0,chatSession:"",bundledKey:false,captureProtection:true,theme:'system',screenAccess:false,turns:[],recordingShortcut:null,native:false,provider:'OpenAI',model:'gpt-realtime-2.1-mini',endpoint:'http://127.0.0.1:11434',keySaved:false,deep:false,pinned:true,answer:'',screen:'',transcript:'',error:'',listening:false,audioBusy:false,reading:false,thinking:false,settings:false,systemAudio:false,autoAssist:false,firstToken:null,screenTime:null,hideShortcut:'⌃ ⌥ Space',pinShortcut:'⌃ ⌥ P',captureShortcut:'⌃ ⌥ S'};

function Mark({ large = false }: {large?: boolean}) { return <svg className={large?'brand-mark large':'brand-mark'} viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="M10 6v14a6 6 0 006 6h10M17 6v10a3 3 0 003 3h6" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round"/><circle cx="25" cy="8" r="2.5" fill="currentColor"/></svg> }
function KeyCaps({value}: {value:string}) { return <span className="keycaps">{value.split(' ').filter(Boolean).map((key,i)=><kbd key={i}>{key}</kbd>)}</span> }
function IconAction({label, children, onClick, active=false}: {label:string;children:React.ReactNode;onClick:()=>void;active?:boolean}) { return <Tooltip content={label}><IconButton variant="ghost" color="gray" className={active?'icon-action active':'icon-action'} aria-label={label} onClick={onClick}>{children}</IconButton></Tooltip> }

function App() {
  const [systemDark,setSystemDark] = useState(window.matchMedia('(prefers-color-scheme: dark)').matches);
  const [state,setState] = useState<Snapshot>(initial);
  const [page,setPage] = useState('assistant');
  const [settingsTab,setSettingsTab] = useState('general');
  const [shortcutsOpen,setShortcutsOpen] = useState(false);
  const [prompt,setPrompt] = useState('');
  const [asked,setAsked] = useState('');
  const [key,setKey] = useState('');
  const [recording,setRecording] = useState<'hide'|'pin'|'capture'|null>(null);
  const [recordError,setRecordError] = useState('');
  const [copied,setCopied] = useState<string|null>(null);
  const [previewNotice,setPreviewNotice] = useState('');
  const input = useRef<HTMLTextAreaElement>(null);
  const answerArea = useRef<HTMLDivElement>(null);
  const nearBottom = useRef(true);
  const resolvedTheme = state.theme === 'system' ? (systemDark?'dark':'light') : state.theme;
  const liveTranscript = useRef<HTMLDivElement>(null);
  const busy = state.thinking || state.reading;
  const configure = (data: Record<string,unknown>) => send({action:'configure',...data});

  function send(command: Command) {
    if (window.webkit?.messageHandlers.lully) { window.webkit.messageHandlers.lully.postMessage(command); return; }
    // Browser-only visual preview never captures data, saves keys, or calls a provider.
    if(command.action==='configure') {
      const {action,...changes}=command;
      if(changes.provider) changes.model = changes.provider==='Gemini'?'gemini-3.8-flash':changes.provider==='OpenAI'?'gpt-5.6-sol':'';
      setState(s=>({...s,...changes}));
    } else if(command.action==='pin') setState(s=>({...s,pinned:!s.pinned}));
    else if(command.action==='settings') setState(s=>({...s,settings:Boolean(command.open)}));
    else if(command.action==='clear') {setState(s=>({...s,turns:[],answer:'',screen:'',transcript:''}));setAsked('');}
    else if(command.action==='dismissError') setState(s=>({...s,error:''}));
    else if(command.action==='saveShortcut') {
      const spec=command.spec as {key:string;control:boolean;option:boolean;shift:boolean;command:boolean};
      const label=[spec.control?'⌃':'',spec.option?'⌥':'',spec.shift?'⇧':'',spec.command?'⌘':'',spec.key.replace('Key','').replace('Digit','')].filter(Boolean).join(' ');
      setState(s=>({...s,[command.target==='hide'?'hideShortcut':command.target==='pin'?'pinShortcut':'captureShortcut']:label}));
    } else if(!['ready','drag','recordShortcut','cancelShortcut'].includes(command.action)) setPreviewNotice('Open the native Lully app to use this action. This is a UI preview.');
  }

  useEffect(()=>{
    const media=window.matchMedia('(prefers-color-scheme: dark)');
    const update=()=>setSystemDark(media.matches);
    media.addEventListener('change',update);
    const pointer=()=>{document.documentElement.dataset.input='pointer';};
    const keyboard=(event:KeyboardEvent)=>{if(event.key==='Tab')document.documentElement.dataset.input='keyboard';};
    document.addEventListener('pointerdown',pointer,true);document.addEventListener('keydown',keyboard,true);
    return ()=>{media.removeEventListener('change',update);document.removeEventListener('pointerdown',pointer,true);document.removeEventListener('keydown',keyboard,true);};
  },[]);
  useEffect(()=>{if(state.chatSession){setPage('assistant');setPrompt('');setAsked('');nearBottom.current=true;}},[state.chatSession]);
  useEffect(()=>{if(liveTranscript.current)liveTranscript.current.scrollTop=liveTranscript.current.scrollHeight;},[state.transcript]);
  useEffect(()=>{
    window.lullyReceive=(data)=>{setState(data);setRecording(data.recordingShortcut);};
    send({action:'ready'});
    return ()=>{delete window.lullyReceive;};
  },[]);
  useLayoutEffect(()=>{
    if(!state.focusRequest)return;
    const frame=requestAnimationFrame(()=>input.current?.focus());
    return ()=>cancelAnimationFrame(frame);
  },[state.focusRequest]);
  // Start with one line, growing only for actual multiline input.
  useLayoutEffect(()=>{
    const field=input.current;
    if(!field)return;
    field.style.height='0px';
    const limit=Math.min(96,Math.max(54,window.innerHeight*0.18));
    field.style.height=`${Math.min(limit,Math.max(32,field.scrollHeight))}px`;
    field.style.overflowY=field.scrollHeight>limit?'auto':'hidden';
  },[prompt,state.settings]);
  // Scroll after the new question renders, without waiting for the first token.
  useLayoutEffect(()=>{
    nearBottom.current=true;
    if(answerArea.current) answerArea.current.scrollTop=answerArea.current.scrollHeight;
  },[state.turns.length]);
  useEffect(()=>{ if(state.answer && nearBottom.current && answerArea.current) answerArea.current.scrollTop=answerArea.current.scrollHeight; },[state.answer]);
  useEffect(()=>{
    if(!recording || state.native) return;
    const cancel=()=>{setRecording(null);send({action:'cancelShortcut'});};
    const handler=(event: KeyboardEvent)=>{
      event.preventDefault();event.stopPropagation();
      if(event.code==='Escape'){cancel();return;}
      if(['Meta','Alt','Control','Shift'].includes(event.key)) return;
      if(!(event.metaKey||event.altKey||event.ctrlKey)){setRecordError('Include ⌘, ⌥, or ⌃ in your shortcut.');return;}
      if(!/^(Key[A-Z]|Digit[0-9]|Space|F([1-9]|1[0-2]))$/.test(event.code)){setRecordError('Use a letter, number, Space, or F1–F12.');return;}
      send({action:'saveShortcut',target:recording,spec:{key:event.code,command:event.metaKey,option:event.altKey,control:event.ctrlKey,shift:event.shiftKey}});
      setRecording(null);setRecordError('');
    };
    window.addEventListener('keydown',handler,true);
    window.addEventListener('blur',cancel);
    return ()=>{window.removeEventListener('keydown',handler,true);window.removeEventListener('blur',cancel);};
  },[recording,state.native]);

  function ask(text = prompt) {
    if(busy) return;
    nearBottom.current=true;
    setAsked(text.trim() || 'Help me with what’s on my screen.');
    send({action:'ask',prompt:text});
    setPrompt('');setPage('assistant');
  }
  function capture(text = prompt) {
    if(busy) return;
    const request=text.trim() || 'Help me with this screen.';
    setAsked(request);send({action:'capture',prompt:request});setPrompt('');setPage('assistant');nearBottom.current=true;
  }
  function openSettings(tab='general') { setSettingsTab(tab);send({action:'settings',open:true}); }
  function closeSettings() { if(recording){send({action:'cancelShortcut'});setRecording(null);}send({action:'settings',open:false});setKey(''); }
  function record(target:'hide'|'pin'|'capture') { setRecordError('');setRecording(target);send({action:'recordShortcut',target}); }

  return <Theme appearance={resolvedTheme} data-theme={resolvedTheme} accentColor="jade" grayColor="sage" radius="medium" scaling="100%"><main className="shell">
    <header className="titlebar">
      <div className="brand" onMouseDown={()=>send({action:'drag'})}><Mark/><span>lully<span className="brand-period">.</span></span></div>
      <div className="window-actions">
        <Tooltip content={state.native?(state.listening?'Audio capture is active':'Ready when you are'):'Browser preview · native actions unavailable'}><span className="connection"><i className={state.listening?'status-dot listening':'status-dot'}/>{state.native?(state.listening?'Listening':'Ready'):'Preview'}</span></Tooltip>
        <span className="action-divider"/>
        <IconAction label={`${state.pinned?'Unpin':'Pin'} window · ${state.pinShortcut}`} active={state.pinned} onClick={()=>send({action:'pin'})}>{state.pinned?<Pin size={16}/>:<PinOff size={16}/>}</IconAction>
        <Popover.Root open={shortcutsOpen} onOpenChange={setShortcutsOpen}>
          <Tooltip content="All keyboard shortcuts"><Popover.Trigger><IconButton aria-label="Show all shortcuts" className={shortcutsOpen?'icon-action active':'icon-action'} variant="ghost" color="gray"><Keyboard size={16}/></IconButton></Popover.Trigger></Tooltip>
          <Popover.Content className="shortcut-reference" side="bottom" align="end" sideOffset={10} aria-label="Keyboard shortcuts">
            <div className="shortcut-reference-heading"><strong>Keyboard shortcuts</strong><Popover.Close><IconButton aria-label="Close shortcuts" variant="ghost" color="gray" size="1"><X size={14}/></IconButton></Popover.Close></div>
            <p>⌘ Command · ⌃ Control · ⌥ Option · ⇧ Shift</p>
            <div className="shortcut-reference-list">{[
              ['Show / hide',state.hideShortcut],['Pin / unpin',state.pinShortcut],['Capture & ask',state.captureShortcut],
              ['Fresh chat','⌃ ⌥ N'],['Focus Ask input','⌃ ⌥ F'],['Move window','⌃ ⌥ ← ↑ ↓ →'],
              ['Opacity ±10%','⌃ ⌥ + / −'],['Resize window','⌘ + / −'],['Send question','↵ or ⌘ ↵'],
              ['New line','⇧ ↵'],['Settings','⌘ ,'],['Copy / cut / paste','⌘ C / X / V'],['Select all','⌘ A'],['Close popup / cancel recording','Esc'],['Quit Lully','⌘ Q']
            ].map(([label,keys])=><div className="shortcut-reference-row" key={label}><span>{label}</span><KeyCaps value={keys}/></div>)}</div>
            <p>Resize and editing keys work while Lully is focused. ⌘ = also enlarges the window.</p>
            <Button variant="soft" color="gray" size="1" onClick={()=>{setShortcutsOpen(false);openSettings('shortcuts');}}>Customize shortcuts<ChevronRight size={13}/></Button>
          </Popover.Content>
        </Popover.Root>
        <IconAction label="Settings" active={state.settings} onClick={()=>state.settings?closeSettings():openSettings()}><Settings2 size={16}/></IconAction>
        <IconAction label={`Hide window · ${state.hideShortcut}`} onClick={()=>send({action:'hide'})}><Minus size={17}/></IconAction>
      </div>
    </header>

    {state.settings ? <>
      <Tabs.Root className="settings-tabs" value={settingsTab} onValueChange={value=>{if(recording){send({action:'cancelShortcut'});setRecording(null);}setSettingsTab(value);}}>
        <div className="settings-navigation"><IconAction label="Back to assistant · Settings save automatically" onClick={closeSettings}><ArrowLeft size={16}/></IconAction><Tabs.List size="1"><Tabs.Trigger value="general"><SlidersHorizontal size={14}/>General</Tabs.Trigger><Tabs.Trigger value="model"><Sparkles size={14}/>Intelligence</Tabs.Trigger><Tabs.Trigger value="shortcuts"><Keyboard size={14}/>Shortcuts</Tabs.Trigger></Tabs.List></div>
        <div className="settings-scroll">
          <Tabs.Content value="general">
            <SectionLabel title="Appearance"/>
            <SegmentedControl.Root aria-label="Theme" value={state.theme} onValueChange={theme=>configure({theme})} className="theme-control"><SegmentedControl.Item value="light"><Sun size={14}/>Light</SegmentedControl.Item><SegmentedControl.Item value="dark"><Moon size={14}/>Dark</SegmentedControl.Item><SegmentedControl.Item value="system"><Monitor size={14}/>System</SegmentedControl.Item></SegmentedControl.Root>
            <SectionLabel title="Your window"/>
            <SettingRow title="Always on top" description="Keep Lully above your other windows." icon={<Pin size={16}/>}><Switch aria-label="Always on top" checked={state.pinned} onCheckedChange={()=>send({action:'pin'})}/></SettingRow>
            <SettingRow title="Window opacity" description="⌃ ⌥ + / − adjusts by 10%. Saved between launches." icon={<SlidersHorizontal size={16}/>}><div className="opacity-control"><Slider aria-label="Window opacity" value={[Math.round(state.opacity*100)]} min={10} max={100} step={1} onValueChange={values=>configure({opacity:values[0]/100})}/><output>{Math.round(state.opacity*100)}%</output></div></SettingRow>
            <SettingRow title="Capture protection" description="Turn off to include Lully in screenshots and recordings. Automatically turns on whenever Lully starts." icon={<ShieldCheck size={16}/>}><Switch aria-label="Capture protection" checked={state.captureProtection} onCheckedChange={captureProtection=>configure({captureProtection})}/></SettingRow>
            <SectionLabel title="Capture & context"/>
            <div className="capture-setting"><Monitor size={17}/><div><h3>Screen capture is manual</h3><p>Only Capture & ask or your capture shortcut reads the screen. Regular questions and audio assistance do not.</p></div></div>
            <SettingRow title="Screen access" description={state.screenAccess?'Enabled for this installed build.':'Not active for this copy of Lully.'} icon={<ShieldCheck size={16}/>}><Button size="1" variant="soft" color="gray" onClick={()=>send({action:'screenSettings'})}>Open settings</Button></SettingRow>
            {!state.screenAccess&&<p className="field-hint">After updating Lully’s signing identity, re-enable the Applications copy in macOS once, then quit and reopen it.</p>}
            <SettingRow title="Audio source" description="You can also choose directly with My Audio or Media Audio in the chat bar." icon={<AudioLines size={16}/>}><Select.Root value={state.systemAudio?'system':'mic'} onValueChange={v=>configure({systemAudio:v==='system'})} disabled={state.listening||state.audioBusy}><Select.Trigger aria-label="Audio source"/><Select.Content position="popper"><Select.Item value="mic">My Audio · microphone</Select.Item><Select.Item value="system">Media Audio · computer</Select.Item></Select.Content></Select.Root></SettingRow>
            <SettingRow title="Auto-assist" description="Get help after a pause in the conversation." icon={<Zap size={16}/>}><Switch aria-label="Auto-assist" checked={state.autoAssist} onCheckedChange={autoAssist=>configure({autoAssist})}/></SettingRow>
            <div className="info-note"><ShieldCheck size={17}/><div><strong>About capture protection</strong><p>Lully requests exclusion from screen capture. Some macOS recorders can still see it. Test your sharing app before relying on it.</p></div></div>
            <p className="fine-print">Audio transcription runs on your Mac in English. Hiding the panel does not stop listening.</p>
          </Tabs.Content>
          <Tabs.Content value="model">
            <SectionLabel title="The brain behind the answers"/>
            <label className="field-label" htmlFor="provider">AI provider</label>
            <Select.Root value={state.provider} onValueChange={provider=>configure({provider})}><Select.Trigger id="provider" className="full-select"/><Select.Content position="popper"><Select.Item value="Gemini">Google Gemini</Select.Item><Select.Item value="OpenAI">OpenAI</Select.Item><Select.Item value="Ollama">Ollama · local</Select.Item></Select.Content></Select.Root>
            <label className="field-label spaced" htmlFor="model">Model</label><TextField.Root id="model" value={state.model} onChange={e=>configure({model:e.target.value})} placeholder="Enter a model ID" size="3"/>
            {state.provider==='Ollama'?<><label className="field-label spaced" htmlFor="endpoint">Local endpoint</label><TextField.Root id="endpoint" value={state.endpoint} onChange={e=>configure({endpoint:e.target.value})}/><p className="field-hint">Use a model installed in Ollama. Context stays on this Mac.</p></>:<>
              <div className="field-title spaced"><label className="field-label" htmlFor="api-key">API key</label>{state.keySaved&&<span className="saved"><Check size={12}/>{state.bundledKey?'Included in this app':'Saved in Keychain'}</span>}</div>
              {!state.bundledKey&&<div className="key-input"><TextField.Root id="api-key" type="password" value={key} onChange={e=>setKey(e.target.value)} placeholder={state.keySaved?'Enter a key to replace the saved one':'Paste your API key'} autoComplete="off" size="3"><TextField.Slot><KeyRound size={15}/></TextField.Slot></TextField.Root><Button variant="soft" disabled={!key.trim()} onClick={()=>{send({action:'saveKey',key});setKey('');}}>Save key</Button></div>}
              <div className="field-title"><p className="field-hint">{state.bundledKey?'Your OpenAI key is included in this local app build.':'Encrypted in macOS Keychain. Never stored in the UI.'}</p>{state.keySaved&&!state.bundledKey&&<button className="text-button" onClick={()=>send({action:'removeKey'})}>Remove</button>}</div>
              <SectionLabel title="Response style"/>
              <SegmentedControl.Root value={state.deep?'deep':'fast'} onValueChange={v=>configure({deep:v==='deep'})} className="reasoning-control"><SegmentedControl.Item value="fast"><Zap size={14}/>Fast</SegmentedControl.Item><SegmentedControl.Item value="deep"><Sparkles size={14}/>Deep</SegmentedControl.Item></SegmentedControl.Root>
              <p className="field-hint">{state.model.startsWith('gpt-realtime')?(state.deep?'Requests a careful answer with important steps.':'Requests a brief, direct answer over Realtime.'):(state.deep?'More reasoning for complex questions. Answers may take longer.':'Low reasoning effort for quick, everyday assistance.')}</p>
              <div className="info-note"><ShieldCheck size={17}/><p>Capture & ask sends a screenshot to {state.provider}. Regular questions use your text and available audio transcript. Audio auto-assist can send repeated requests.</p></div>
            </>}
          </Tabs.Content>
          <Tabs.Content value="shortcuts">
            <SectionLabel title="Stay in your flow"/>
            <p className="section-description">Control Lully from anywhere. Click a shortcut, then press your preferred combination.</p>
            <ShortcutRow title="Show / hide" description="Bring Lully into view, or tuck it away." icon={<EyeOff size={17}/>} value={state.hideShortcut} active={recording==='hide'} onRecord={()=>record('hide')} onReset={()=>send({action:'resetShortcut',target:'hide'})}/>
            <ShortcutRow title="Pin / unpin" description="Toggle whether Lully stays on top." icon={<Pin size={17}/>} value={state.pinShortcut} active={recording==='pin'} onRecord={()=>record('pin')} onReset={()=>send({action:'resetShortcut',target:'pin'})}/>
            <ShortcutRow title="Capture & ask" description="Capture your screen and get assistance." icon={<ScanLine size={17}/>} value={state.captureShortcut} active={recording==='capture'} onRecord={()=>record('capture')} onReset={()=>send({action:'resetShortcut',target:'capture'})}/>
            <div className="shortcut-fixed movement-shortcuts"><div><span>Move window</span><p>Hold to move smoothly in any direction.</p></div><KeyCaps value="⌃ ⌥ ← ↑ ↓ →"/></div>
            <div className="shortcut-fixed"><div><span>Focus Ask input</span><p>Show Lully and start typing.</p></div><KeyCaps value="⌃ ⌥ F"/></div>
            <div className="shortcut-fixed"><div><span>Fresh chat</span><p>Clear conversation context and stop listening.</p></div><KeyCaps value="⌃ ⌥ N"/></div>
            <div className="shortcut-fixed"><div><span>Window opacity</span><p>Increase or decrease opacity by 10%.</p></div><KeyCaps value="⌃ ⌥ + / −"/></div>
            <div className="shortcut-fixed"><div><span>Resize window</span><p>⌘ + grows · ⌘ − shrinks. Hold to keep resizing while Lully is focused.</p></div><KeyCaps value="⌘ + / −"/></div>
            <div className="shortcut-fixed"><div><span>Send a question</span><p>While the composer is focused.</p></div><KeyCaps value="⌘ ↵"/></div>
            {recording&&<div className="record-notice"><Keyboard size={16}/><span>{recordError||'Listening for your shortcut…'}</span><button className="text-button" onClick={()=>{setRecording(null);send({action:'cancelShortcut'});}}>Cancel</button></div>}
            <div className="info-note"><CircleHelp size={17}/><p>Include ⌘, ⌥, or ⌃ plus a letter, number, Space, or function key. Press Esc to cancel. Shortcuts are saved automatically.</p></div>
          </Tabs.Content>
        </div>
      </Tabs.Root>
      {state.error&&<ErrorNotice text={state.error} onDismiss={()=>send({action:'dismissError'})}/>}
    </> : <>
      <nav className="view-tabs" aria-label="Assistant views"><button className={page==='assistant'?'selected':''} onClick={()=>setPage('assistant')}><Sparkles size={15}/>Assistant</button><button className={page==='context'?'selected':''} onClick={()=>setPage('context')}><ScanLine size={15}/>Context{(state.screen||state.transcript)&&<i/>}</button><div className="tabs-spacer"/><Button className="fresh-chat" variant="ghost" color="gray" size="1" onClick={()=>{send({action:'clear'});setAsked('');setPrompt('');setPage('assistant');}}><RotateCcw size={13}/>Fresh chat</Button></nav>
      {(state.listening||state.audioBusy)&&<aside className="live-transcript" aria-label="Live transcription"><div className="live-transcript-heading"><AudioLines size={14}/><strong>{state.audioBusy?'Connecting audio…':'Live transcript'}</strong><span>{state.systemAudio?'Media Audio':'My Audio'}</span></div><div className="live-transcript-text" ref={liveTranscript} role="log" aria-live="polite" aria-atomic="true">{state.transcript || (state.audioBusy?'Waiting for macOS audio and speech permissions…':'Listening. Speak to see your words here. English transcription runs on this Mac.')}</div><button className="text-button" onClick={()=>setPage('context')}>View full transcript<ChevronRight size={12}/></button></aside>}
      <div className="content-scroll" ref={answerArea} onScroll={()=>{const e=answerArea.current;if(e)nearBottom.current=e.scrollHeight-e.scrollTop-e.clientHeight<70;}}>
        {page==='context'?<div className="context-view"><div className="context-heading"><Monitor size={17}/><h2>Screen context</h2>{state.screenTime&&<span>{new Date(state.screenTime).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}</span>}</div>{state.screen?<pre>{state.screen}</pre>:<div className="context-empty"><p>A clearer picture starts here.</p><span>Capture your main display to give Lully context.</span><Button size="2" variant="soft" color="gray" onClick={()=>capture()} disabled={busy}><ScanLine size={14}/>{state.reading?'Reading…':'Capture & ask'}</Button></div>}<div className="context-heading audio-heading"><AudioLines size={17}/><h2>Audio transcript</h2>{state.listening&&<i className="status-dot listening"/>}</div>{state.transcript?<pre>{state.transcript}</pre>:<p className="context-hint">Your live transcript will appear here when you start listening.</p>}</div>:
          state.turns.length>0?<div className="conversation">{state.turns.map(turn=><section className="chat-turn" key={turn.id}><div className="question"><span>You</span><p>{turn.question}</p></div>{turn.pending&&!turn.answer?<div className="answer-heading" role="status"><span className="answer-status"><LoaderCircle size={12} className="spin"/>{state.reading?'Reading your screen…':'Thinking…'}</span></div>:turn.issue?<div className="answer-heading"><span className="answer-status">Incomplete answer</span></div>:null}{turn.answer?<article className="markdown"><ReactMarkdown remarkPlugins={[remarkGfm]} skipHtml components={{a:({children})=><span className="answer-link">{children}</span>,img:()=>null}}>{turn.answer}</ReactMarkdown></article>:turn.pending?null:<p className="context-hint">{turn.issue||'Response stopped.'}</p>}{turn.answer&&!turn.pending&&<Button className="copy-button" aria-label={copied===turn.id?'Copied':'Copy answer'} title={copied===turn.id?'Copied':'Copy answer'} variant="ghost" color="gray" size="1" onClick={()=>{send({action:'copy',id:turn.id});setCopied(turn.id);window.setTimeout(()=>setCopied(null),1800);}}>{copied===turn.id?<Check size={13}/>:<Copy size={13}/>}</Button>}</section>)}</div>:
          <div className="empty-state"><div className="empty-emblem"><Mark large/></div><span className="eyebrow">A LITTLE CLARITY, ON DEMAND</span><h1>What are we working on?</h1><p>Your screen. Your conversation.<br/>The right help, right here.</p><div className="suggestions"><button onClick={()=>capture('Summarize what is on my screen.')}><ScanLine size={16}/><span>Make sense of my screen</span><ChevronRight size={14}/></button><button onClick={()=>{setPrompt('Help me solve ');input.current?.focus();}}><Sparkles size={16}/><span>Work through a problem</span><ChevronRight size={14}/></button><button onClick={()=>{send({action:'listen'});setPage('context');}} disabled={state.audioBusy}><AudioLines size={16}/><span>{state.listening?'Stop listening':'Listen and follow along'}</span><ChevronRight size={14}/></button></div></div>}
      </div>
      {state.error&&<ErrorNotice text={state.error} onDismiss={()=>send({action:'dismissError'})}/>}
      {previewNotice&&<ErrorNotice text={previewNotice} onDismiss={()=>setPreviewNotice('')}/>}
      <div className="composer-wrap"><div className="composer"><TextArea ref={input} aria-label="Ask Lully" placeholder="Ask Lully anything…" value={prompt} onChange={e=>setPrompt(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'&&(e.metaKey||!e.shiftKey)&&!e.nativeEvent.isComposing){e.preventDefault();ask();}}} resize="none" rows={1}/><div className="composer-toolbar"><Tooltip content={`Capture screen & ask · ${state.captureShortcut}`}><button className="context-chip capture-chip" disabled={busy} onClick={()=>capture()}>{state.reading?<LoaderCircle size={13} className="spin"/>:<ScanLine size={13}/>}<span>{state.reading?'Capturing…':'Capture & ask'}</span></button></Tooltip>{([{systemAudio:false,label:'My Audio',description:'your microphone',Icon:Mic},{systemAudio:true,label:'Media Audio',description:'computer sound',Icon:Volume2}] as const).map(source=>{const active=state.listening&&state.systemAudio===source.systemAudio;const connecting=state.audioBusy&&state.systemAudio===source.systemAudio;return <Tooltip key={source.label} content={active?`Stop listening to ${source.description}`:`Listen to ${source.description}${state.listening?' · switches audio source':''}`}><button aria-label={source.label} aria-pressed={active} className={active?'context-chip live':'context-chip'} disabled={state.audioBusy} onClick={()=>send({action:'listen',systemAudio:source.systemAudio})}>{connecting?<LoaderCircle size={13} className="spin"/>:<source.Icon size={13}/>}<span>{source.label}</span>{active&&<i className="audio-live-dot"/>}</button></Tooltip>})}<span className="toolbar-spacer"/>{state.thinking?<IconButton aria-label="Stop response" className="send-button" variant="solid" onClick={()=>send({action:'cancel'})}><Square size={14} fill="currentColor"/></IconButton>:<Tooltip content="Send · ⌘ Enter"><IconButton aria-label="Send question" className="send-button" variant="solid" disabled={busy} onClick={()=>ask()}><ArrowUp size={18}/></IconButton></Tooltip>}</div></div>
      </div>
      <footer className="statusbar"><button className="model-link" aria-label="Model settings" onClick={()=>openSettings('model')}><span className="mini-dot"/>{state.provider==='Gemini'?'Gemini':state.provider==='OpenAI'?'OpenAI':'Local'}<span className="meta-separator">·</span>{state.deep?'Deep':'Fast'}<ChevronRight size={11}/></button><Tooltip content={state.captureProtection?"Capture protection is enabled, but some recorders may still see Lully. Click for settings.":"Lully is visible in screenshots and recordings. Protection turns on next launch."}><button onClick={()=>openSettings('general')}><ShieldCheck size={11}/>{state.captureProtection?'Protection on':'Protection off'}</button></Tooltip></footer>
    </>}
  </main></Theme>;
}
function SectionLabel({title}: {title:string}) {return <h2 className="section-label">{title}</h2>}
function SettingRow({title,description,icon,children}: {title:string;description:string;icon:React.ReactNode;children:React.ReactNode}) {return <div className="setting-row"><span className="setting-icon">{icon}</span><div className="setting-copy"><h3>{title}</h3><p>{description}</p></div>{children}</div>}
function ShortcutRow({title,description,icon,value,active,onRecord,onReset}: {title:string;description:string;icon:React.ReactNode;value:string;active:boolean;onRecord:()=>void;onReset:()=>void}) {return <div className="shortcut-row"><div className="shortcut-title">{icon}<div><h3>{title}</h3><p>{description}</p></div></div><div className="shortcut-input"><Button aria-label={`Record ${title} shortcut`} variant="surface" color={active?'jade':'gray'} className={active?'record-button recording':'record-button'} onClick={onRecord}>{active?<span>Press a shortcut…</span>:<KeyCaps value={value}/>}<Keyboard size={14}/></Button><Tooltip content="Restore default"><IconButton aria-label={`Reset ${title} shortcut`} variant="ghost" color="gray" onClick={onReset}><RotateCcw size={14}/></IconButton></Tooltip></div></div>}
function ErrorNotice({text,onDismiss}: {text:string;onDismiss:()=>void}) {return <div className="error-notice" role="alert"><span>{text}</span><IconButton aria-label="Dismiss message" variant="ghost" color="gray" size="1" onClick={onDismiss}><X size={14}/></IconButton></div>}

if (!window.webkit?.messageHandlers.lully) document.body.classList.add('browser-preview');
createRoot(document.getElementById('root')!).render(<App/>);
