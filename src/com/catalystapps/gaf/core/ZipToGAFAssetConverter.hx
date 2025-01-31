package com.catalystapps.gaf.core;

import com.catalystapps.gaf.data.GAFAsset;
import com.catalystapps.gaf.data.GAFAssetConfig;
import com.catalystapps.gaf.data.GAFBundle;
import com.catalystapps.gaf.data.GAFGFXData;
import com.catalystapps.gaf.data.GAFTimeline;
import com.catalystapps.gaf.data.GAFTimelineConfig;
import com.catalystapps.gaf.data.config.CSound;
import com.catalystapps.gaf.data.converters.BinGAFAssetConfigConverter;
import com.catalystapps.gaf.data.converters.ErrorConstants;
import com.catalystapps.gaf.data.tagfx.GAFATFData;
import com.catalystapps.gaf.data.tagfx.TAGFXBase;
import com.catalystapps.gaf.data.tagfx.TAGFXSourceATFURL;
import com.catalystapps.gaf.data.tagfx.TAGFXSourceBitmapData;
import com.catalystapps.gaf.data.tagfx.TAGFXSourcePNGBA;
import com.catalystapps.gaf.data.tagfx.TAGFXSourcePNGURL;
import com.catalystapps.gaf.sound.GAFSoundData;
import com.catalystapps.gaf.utils.FileUtils;
import com.catalystapps.gaf.utils.MathUtility;
import haxe.Timer;
import openfl.display3D.Context3DTextureFormat;
import openfl.errors.Error;
import openfl.events.ErrorEvent;
import openfl.events.Event;
import openfl.events.EventDispatcher;
import openfl.events.IOErrorEvent;
import openfl.geom.Point;
import openfl.media.Sound;
import openfl.net.URLLoader;
import openfl.net.URLLoaderDataFormat;
import openfl.net.URLRequest;
import openfl.utils.ByteArray;
import openfl.utils.CompressionAlgorithm;
import openfl.utils.Endian;
import starling.core.Starling;

#if ZIP_LIB
import zip.Zip;
import zip.ZipEntry;
import zip.ZipReader;
#else
import haxe.zip.Entry as ZipEntry;
import haxe.zip.Reader as ZipReader;
#end

/** Dispatched when convertation completed */
@:meta(Event(name="complete",type="flash.events.Event"))

/** Dispatched when conversion failed for some reason */
@:meta(Event(name="error",type="flash.events.ErrorEvent"))

/**
 * The ZipToGAFAssetConverter simply converts loaded GAF file into <code>GAFTimeline</code> object that
 * is used to create <code>GAFMovieClip</code> - animation display object ready to be used in starling display list.
 * If GAF file is created as Bundle it converts as <code>GAFBundle</code>
 *
 * <p>Here is the simple rules to understand what is <code>GAFTimeline</code>, <code>GAFBundle</code> and <code>GAFMovieClip</code>:</p>
 *
 * <ul>
 *    <li><code>GAFTimeline</code> - is like a library symbol in Flash IDE. When you load GAF asset file you can not use it directly.
 *        All you need to do is convert it into <code>GAFTimeline</code> using ZipToGAFAssetConverter</li>
 *    <li><code>GAFBundle</code> - is a storage of all <code>GAFTimeline's</code> from Bundle</li>
 *    <li><code>GAFMovieClip</code> - is like an instance of Flash <code>MovieClip</code>.
 *        You can create it from <code>GAFTimeline</code> and use in <code>Starling Display Object</code></li>
 * </ul>
 *
 * @see com.catalystapps.gaf.data.GAFTimeline
 * @see com.catalystapps.gaf.data.GAFBundle
 * @see com.catalystapps.gaf.display.GAFMovieClip
 *
 */

class ZipToGAFAssetConverter extends EventDispatcher
{
    public var gafBundle(get, never) : GAFBundle;
    public var gafTimeline(get, never) : GAFTimeline;
    public var zip(get, never) : ZipReader;
    public var zipLoader(get, never) : Map<String, ZipEntry>;
	
    public var id(get, set) : String;
    public var parseConfigAsync(get, set) : Bool;
    public var ignoreSounds(never, set) : Bool;

    //--------------------------------------------------------------------------
    //
    //  PUBLIC VARIABLES
    //
    //--------------------------------------------------------------------------
    
    /**
	 * In process of conversion doesn't create textures (doesn't load in GPU memory).
	 * Be sure to set up <code>Starling.handleLostContext = true</code> when using this action, otherwise Error will occur
	 */
    public static inline var ACTION_DONT_LOAD_IN_GPU_MEMORY : String = "actionDontLoadInGPUMemory";
    
    /**
	 * In process of conversion create textures (load in GPU memory).
	 */
    public static inline var ACTION_LOAD_ALL_IN_GPU_MEMORY : String = "actionLoadAllInGPUMemory";
    
    /**
	 * In process of conversion create textures (load in GPU memory) only atlases for default scale and csf
	 */
    public static inline var ACTION_LOAD_IN_GPU_MEMORY_ONLY_DEFAULT : String = "actionLoadInGPUMemoryOnlyDefault";
    
    /**
	 * Action that should be applied to atlases in process of conversion. Possible values are action constants.
	 * By default loads in GPU memory only atlases for default scale and csf
	 */
    public static var actionWithAtlases : String = ACTION_LOAD_IN_GPU_MEMORY_ONLY_DEFAULT;
    
    /**
	 * Defines the values to use for specifying a texture format.
	 * If you prefer to use 16 bit-per-pixel textures just set
	 * <code>Context3DTextureFormat.BGR_PACKED</code> or <code>Context3DTextureFormat.BGRA_PACKED</code>.
	 * It will cut texture memory usage in half.
	 */
    public var textureFormat : String = Context3DTextureFormat.BGRA;
    
    /**
	 * Indicates keep or not to keep zip file content as ByteArray for further usage.
	 * It's available through get <code>zip</code> property.
	 * By default converter won't keep zip content for further usage.
	 */
    public static var keepZipInRAM : Bool = false;
	
    //--------------------------------------------------------------------------
    //
    //  PRIVATE VARIABLES
    //
    //--------------------------------------------------------------------------
    private var _id : String;
    
	private var _zip : ZipReader;
	private var _zipLoader : Map<String, ZipEntry>;
    
    private var _currentConfigIndex : Int;
    
    private var _gafAssetsIDs : Array<String>;
    private var _gafAssetConfigs : Map<String, GAFAssetConfig>;
    private var _gafAssetConfigSources : Map<String, ByteArray>;
    
    private var _sounds : Map<String, ByteArray>;
    private var _taGFXs : Map<String, TAGFXBase>;
    
    private var _gfxData : GAFGFXData;
    private var _soundData : GAFSoundData;
    
    private var _gafBundle : GAFBundle;
    
    private var _defaultScale : Null<Float> = null;
    private var _defaultContentScaleFactor : Null<Float> = null;
    
    private var _parseConfigAsync : Bool;
    private var _ignoreSounds : Bool;
    
    ///////////////////////////////////
    
    private var _gafAssetsConfigURLs : Array<String>;
    private var _gafAssetsConfigIndex : Int;
    
    private var _atlasSourceURLs : Array<String>;
    private var _atlasSourceIndex : Int;
    
    //--------------------------------------------------------------------------
    //
    //  CONSTRUCTOR
    //
    //--------------------------------------------------------------------------
    
    /** Creates a new <code>ZipToGAFAssetConverter</code> instance.
	 * @param id The id of the converter.
	 * If it is not empty <code>ZipToGAFAssetConverter</code> sets the <code>name</code> of produced bundle equal to this id.
	 */
    public function new(id : String = null)
    {
        super();
        this._id = id;
    }
    
    //--------------------------------------------------------------------------
    //
    //  PUBLIC METHODS
    //
    //--------------------------------------------------------------------------
    
    /**
	 * Converts GAF file (*.zip) into <code>GAFTimeline</code> or <code>GAFBundle</code> depending on file content.
	 * Because conversion process is asynchronous use <code>Event.COMPLETE</code> listener to trigger successful conversion.
	 * Use <code>ErrorEvent.ERROR</code> listener to trigger any conversion fail.
	 *
	 * @param data *.zip file binary or File object represents a path to a *.gaf file or directory with *.gaf config files
	 * @param defaultScale Scale value for <code>GAFTimeline</code> that will be set by default
	 * @param defaultContentScaleFactor Content scale factor (csf) value for <code>GAFTimeline</code> that will be set by default
	 */
    public function convert(data : Dynamic, defaultScale : Null<Float> = null, defaultContentScaleFactor : Null<Float> = null) : Void
    {
        if (ZipToGAFAssetConverter.actionWithAtlases == ZipToGAFAssetConverter.ACTION_DONT_LOAD_IN_GPU_MEMORY)
        {
            throw new Error("Impossible parameters combination! Starling.handleLostContext = false and actionWithAtlases = ACTION_DONT_LOAD_ALL_IN_VIDEO_MEMORY One of the parameters must be changed!");
        }
		
        this.reset();
        
        this._defaultScale = defaultScale;
        this._defaultContentScaleFactor = defaultContentScaleFactor;
        
        if (this._id != null && this._id.length > 0)
        {
            this._gafBundle.name = this._id;
        }
        
        //if (Std.isOfType(data, ByteArray))
		var byteArray:ByteArray;
		if(data != null && (byteArray = data) != null)
        {
			var zipOk:Bool = true;
			try
			{
				#if ZIP_LIB
				_zip = new ZipReader(byteArray);
				#else
				_zip = new ZipReader(new haxe.io.BytesInput(haxe.io.Bytes.ofData(byteArray)));
				#end
			}
			catch (e:Dynamic)
			{
				trace("zip create error", e);
				onParseError();
				zipOk = false;
			}
			
			if (zipOk)
			{
				try
				{
					var entry:ZipEntry;
					_zipLoader = new Map();
					
					#if ZIP_LIB
					while ((entry = _zip.getNextEntry()) != null)
					{
						_zipLoader.set(entry.fileName, entry);
					}
					#else
					var entries = _zip.read();
					for (entry in entries)
					{
						_zipLoader.set(entry.fileName, entry);
					}
					#end
				}
				catch (e:Dynamic)
				{
					trace("zip read error", e);
					onParseError();
					zipOk = false;
				}
			}
			
			if (zipOk)
			{
				parseZip();
			}
            
            if (!ZipToGAFAssetConverter.keepZipInRAM)
            {
                cast(data, ByteArray).clear();
            }
        }
/*
        else if (data != null && (Std.isOfType(data, Array) || Type.getClassName(data) == "flash.filesystem::File"))
        {
            this._gafAssetsConfigURLs = [];
            
            if (Std.isOfType(data, Array))
            {
				// AS3HX WARNING could not determine type for var: file exp: EIdent(data) type: Dynamic /
                for (file in data)
                {
                    this.processFile(file);
                }
            }
            else
            {
                this.processFile(data);
            }
            
            if (this._gafAssetsConfigURLs.length)
            {
                this.loadConfig();
            }
            else
            {
                this.zipProcessError(ErrorConstants.GAF_NOT_FOUND, 5);
            }
        }
*/
        //else if (Std.isOfType(data, Dynamic) && data.configs && data.atlases)
        else if (data != null && (Reflect.hasField(data, "configs") && Reflect.hasField(data, "atlases")))
        {
            this.parseObject(data);
        }
        else
        {
            this.zipProcessError(ErrorConstants.UNKNOWN_FORMAT, 6);
        }
    }
    
    //--------------------------------------------------------------------------
    //
    //  PRIVATE METHODS
    //
    //--------------------------------------------------------------------------
    
    private function reset() : Void
    {
        this._zip = null;
        this._zipLoader = null;
        this._currentConfigIndex = 0;
        
        this._sounds = new Map();
        this._taGFXs = new Map();
        
        this._gfxData = new GAFGFXData();
        this._soundData = new GAFSoundData();
        this._gafBundle = new GAFBundle();
        this._gafBundle.soundData = this._soundData;
        
        this._gafAssetsIDs = [];
        this._gafAssetConfigs = new Map();
        this._gafAssetConfigSources = new Map();
        
        this._gafAssetsConfigURLs = [];
        this._gafAssetsConfigIndex = 0;
        
        this._atlasSourceURLs = [];
        this._atlasSourceIndex = 0;
    }
    
    //private function parseObject(data : Dynamic) : Void
    private function parseObject(data : {configs:Array<Dynamic>, atlases:Array<Dynamic>}) : Void
    {
		this._taGFXs = new Map();
        
		// AS3HX WARNING could not determine type for var: configObj exp: EField(EIdent(data),configs) type: null //
        for (configObj in data.configs)
        {
            this._gafAssetsIDs.push(configObj.name);
            
            var ba : ByteArray = cast(configObj.config, ByteArray);
            ba.position = 0;
            
            if (configObj.type == "gaf")
            {
                this._gafAssetConfigSources.set(configObj.name, ba);
            }
            else
            {
                this.zipProcessError(ErrorConstants.UNSUPPORTED_JSON);
            }
        }
        
		// AS3HX WARNING could not determine type for var: atlasObj exp: EField(EIdent(data),atlases) type: null //
        for (atlasObj in data.atlases)
        {
            var taGFX : TAGFXBase = new TAGFXSourceBitmapData(atlasObj.bitmapData, this.textureFormat);
            this._taGFXs.set(atlasObj.name, taGFX);
        }
        
        ///////////////////////////////////
        
        this.convertConfig();
    }
    
/*
    private function processFile(data : Dynamic) : Void
    {
        if (Type.getClassName(data) == "flash.filesystem::File")
        {
            if (Reflect.field(data, "exists") == null || Reflect.field(data, "isHidden") != null)
            {
                this.zipProcessError(ErrorConstants.FILE_NOT_FOUND + Reflect.field(data, "url") + "'", 4);
            }
            else
            {
                var url : String;
                
                if (Reflect.field(data, "isDirectory") != null)
                {
                    var files : Array<Dynamic> = Reflect.field(data, "getDirectoryListing")();
                    
                    for (file in files)
                    {
                        if (Reflect.field(file, "exists") != null && Reflect.field(file, "isHidden") == null && Reflect.field(file, "isDirectory") == null)
                        {
                            url = Reflect.field(file, "url");
                            
                            if (isGAFConfig(url))
                            {
                                this._gafAssetsConfigURLs.push(url);
                            }
                            else if (isJSONConfig(url))
                            {
                                this.zipProcessError(ErrorConstants.UNSUPPORTED_JSON);
                                return;
                            }
                        }
                    }
                }
                else
                {
                    url = Reflect.field(data, "url");
                    
                    if (isGAFConfig(url))
                    {
                        this._gafAssetsConfigURLs.push(url);
                    }
                    else if (isJSONConfig(url))
                    {
                        this.zipProcessError(ErrorConstants.UNSUPPORTED_JSON);
                    }
                }
            }
        }
    }
*/
    
    private function findAllAtlasURLs() : Void
    {
        this._atlasSourceURLs = [];
        
        var url : String;
        var gafTimelineConfigs : Array<GAFTimelineConfig>;
        
        for (id in this._gafAssetConfigs.keys())
        {
            gafTimelineConfigs = this._gafAssetConfigs.get(id).timelines;
            
            for (config in gafTimelineConfigs)
            {
                var folderURL : String = getFolderURL(id);
                
                for (scale in config.allTextureAtlases)
                {
                    if ((this._defaultScale == null) || MathUtility.equals(scale.scale, this._defaultScale))
                    {
                        for (csf in scale.allContentScaleFactors)
                        {
                            if ((this._defaultContentScaleFactor == null) || MathUtility.equals(csf.csf, this._defaultContentScaleFactor))
                            {
                                for (source in csf.sources)
                                {
                                    url = folderURL + source.source;
                                    
                                    if (source.source != "no_atlas" && this._atlasSourceURLs.indexOf(url) == -1)
                                    {
                                        this._atlasSourceURLs.push(url);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if (this._atlasSourceURLs.length > 0)
        {
            this.loadNextAtlas();
        }
        else
        {
            this.createGAFTimelines();
        }
    }
    
    private function loadNextAtlas() : Void
    {
        var url : String = this._atlasSourceURLs[this._atlasSourceIndex];
        var fileName : String = url.substring(url.lastIndexOf("/") + 1);
        
        var textureSize : Point;
        var taGFX : TAGFXBase;
        var FileClass : Class<Dynamic> = Type.getClass(Type.resolveClass("flash.filesystem::File"));
        var file : Dynamic = Type.createInstance(FileClass, [url]);
        if (Reflect.field(file, "exists") != null)
        {
            textureSize = FileUtils.getPNGSize(file);
            taGFX = new TAGFXSourcePNGURL(url, textureSize, this.textureFormat);
            
            this._taGFXs.set(fileName, taGFX);
        }
        else
        {
            url = url.substring(0, url.lastIndexOf(".png")) + ".atf";
            file = Type.createInstance(FileClass, [url]);
            if (Reflect.field(file, "exists") != null)
            {
                var atfData : GAFATFData = FileUtils.getATFData(file);
                taGFX = new TAGFXSourceATFURL(url, atfData);
                
                this._taGFXs.set(fileName, taGFX);
            }
            else
            {
                this.zipProcessError(ErrorConstants.FILE_NOT_FOUND + url + "'", 4);
            }
        }
        
        this._atlasSourceIndex++;
        
        if (this._atlasSourceIndex >= this._atlasSourceURLs.length)
        {
            this.createGAFTimelines();
        }
        else
        {
            this.loadNextAtlas();
        }
    }
    
    private function loadConfig() : Void
    {
        var url : String = this._gafAssetsConfigURLs[this._gafAssetsConfigIndex];
        var gafAssetsConfigURLLoader : URLLoader = new URLLoader();
        gafAssetsConfigURLLoader.dataFormat = URLLoaderDataFormat.BINARY;
        gafAssetsConfigURLLoader.addEventListener(IOErrorEvent.IO_ERROR, this.onConfigIOError);
        gafAssetsConfigURLLoader.addEventListener(Event.COMPLETE, this.onConfigLoadComplete);
        gafAssetsConfigURLLoader.load(new URLRequest(url));
    }
    
    private function finalizeParsing() : Void
    {
        this._taGFXs = null;
        this._sounds = null;
        
		if (!ZipToGAFAssetConverter.keepZipInRAM)
		{
			
			if (this.zipLoader != null)
			{
				for (entry in zipLoader)
				{
					entry = null;
				}
				
				this._zipLoader = null;
			}
			
			if (this._zip != null)
			{
				#if ZIP_LIB
				this._zip.clean();
				#end
				
				this._zip = null;
			}
		}
        
        if (this._gfxData.isTexturesReady)
        {
            this.dispatchEvent(new Event(Event.COMPLETE));
        }
        else
        {
            this._gfxData.addEventListener(GAFGFXData.EVENT_TYPE_TEXTURES_READY, this.onTexturesReady);
        }
    }
    
    private static function getFolderURL(url : String) : String
    {
        var cutURL : String = url.split("?")[0];
        
        var lastIndex : Int = cutURL.lastIndexOf("/");
        
        return cutURL.substring(0, lastIndex + 1);
    }
    
    private static function isJSONConfig(url : String) : Bool
    {
        return (url.split("?")[0].split(".").pop().toLowerCase() == "json");
    }
    
    private static function isGAFConfig(url : String) : Bool
    {
        return (url.split("?")[0].split(".").pop().toLowerCase() == "gaf");
    }
    
    private function parseZip() : Void
    {
        var zipFile : ByteArray;
		
        var fileName : String;
        var taGFX : TAGFXBase;
        
        this._taGFXs = new Map();
        
        this._gafAssetConfigSources = new Map();
        this._gafAssetsIDs = [];
        
		for (path in zipLoader.keys())
		{
			fileName = path;
			#if ZIP_LIB
			zipFile = Zip.getBytes(zipLoader.get(path));
			#else
			zipFile = getBytes(zipLoader.get(path));
			#end
			zipFile.endian = Endian.BIG_ENDIAN;
            
            switch (fileName.substr(fileName.toLowerCase().lastIndexOf(".")))
            {
                case ".png":
                    fileName = fileName.substring(fileName.lastIndexOf("/") + 1);
                    var pngBA : ByteArray = zipFile;
                    var pngSize : Point = FileUtils.getPNGBASize(pngBA);
                    taGFX = new TAGFXSourcePNGBA(pngBA, pngSize, this.textureFormat);
                    this._taGFXs.set(fileName, taGFX);
					//trace("parseZip : png", pngSize, pngBA.length);
/*
                case ".atf":
                    fileName = fileName.substring(fileName.lastIndexOf("/") + 1, fileName.toLowerCase().lastIndexOf(".atf")) + ".png";
                    taGFX = new TAGFXSourceATFBA(zipFile.content);
                    this._taGFXs.set(fileName, taGFX);
*/
                case ".gaf":
                    this._gafAssetsIDs.push(fileName);
                    this._gafAssetConfigSources.set(fileName, zipFile);
					//trace("parseZip : gaf");
                case ".json":
                    this.zipProcessError(ErrorConstants.UNSUPPORTED_JSON);
                case ".mp3", ".wav":
                    if (!this._ignoreSounds)
                    {
                        this._sounds.set(fileName, zipFile);
                    }
            }
        }
        
        this.convertConfig();
    }
    
    private function convertConfig() : Void
    {
        var configID : String = this._gafAssetsIDs[this._currentConfigIndex];
        var configSource : Dynamic = this._gafAssetConfigSources.get(configID);
        var gafAssetID : String = this.getAssetId(this._gafAssetsIDs[this._currentConfigIndex]);
        
        //if (Std.isOfType(configSource, ByteArray))
        if (cast(configSource, ByteArray) != null)
        {
            var converter : BinGAFAssetConfigConverter = new BinGAFAssetConfigConverter(gafAssetID, cast(configSource, ByteArray));
            converter.defaultScale = this._defaultScale;
            converter.defaultCSF = this._defaultContentScaleFactor;
            converter.ignoreSounds = this._ignoreSounds;
            converter.addEventListener(Event.COMPLETE, onConverted);
            converter.addEventListener(ErrorEvent.ERROR, onConvertError);
            converter.convert(this._parseConfigAsync);
        }
        else
        {
            throw new Error();
        }
    }
    
    private function createGAFTimelines(event : Event = null) : Void
    {
        if (event != null)
        {
            Starling.current.stage3D.removeEventListener(Event.CONTEXT3D_CREATE, createGAFTimelines);
        }
        if (!Starling.current.contextValid)
        {
            Starling.current.stage3D.addEventListener(Event.CONTEXT3D_CREATE, createGAFTimelines);
        }
        
        var gafTimelineConfigs : Array<GAFTimelineConfig>;
        var gafAssetConfigID : String;
        var gafAssetConfig : GAFAssetConfig = null;
        var gafAsset : GAFAsset = null;
        var i : Int;
        
        for (taGFX in this._taGFXs)
        {
            taGFX.clearSourceAfterTextureCreated = false;
        }
        
		for (i in 0...this._gafAssetsIDs.length) 
		{
            gafAssetConfigID = this._gafAssetsIDs[i];
            gafAssetConfig = this._gafAssetConfigs.get(gafAssetConfigID);
            gafTimelineConfigs = gafAssetConfig.timelines;
            
            gafAsset = new GAFAsset(gafAssetConfig);
            for (config in gafTimelineConfigs)
            {
                gafAsset.addGAFTimeline(this.createTimeline(config, gafAsset));
            }
            
            this._gafBundle.addGAFAsset(gafAsset);
        }
        
        if (gafAsset == null || gafAsset.timelines.length == 0)
        {
            this.zipProcessError(ErrorConstants.TIMELINES_NOT_FOUND);
            return;
        }
        
        if (this._gafAssetsIDs.length == 1)
        {
            //this._gafBundle.name ||= gafAssetConfig.id;
            if(this._gafBundle.name == null) this._gafBundle.name = gafAssetConfig.id;
        }
        
        if (this._soundData.hasSoundsToLoad && !this._ignoreSounds)
        {
            this._soundData.loadSounds(this.finalizeParsing, this.onSoundLoadIOError);
        }
        else
        {
            this.finalizeParsing();
        }
    }
    
    private function createTimeline(config : GAFTimelineConfig, asset : GAFAsset) : GAFTimeline
    {
        for (cScale in config.allTextureAtlases)
        {
            if ((this._defaultScale == null) || MathUtility.equals(this._defaultScale, cScale.scale))
            {
                for (cCSF in cScale.allContentScaleFactors)
                {
                    if ((this._defaultContentScaleFactor == null) || MathUtility.equals(this._defaultContentScaleFactor, cCSF.csf))
                    {
                        for (taSource in cCSF.sources)
                        {
                            if (taSource.source == "no_atlas")
                            {
                                continue;
                            }
                            if (this._taGFXs.get(taSource.source) != null)
                            {
                                var taGFX : TAGFXBase = this._taGFXs.get(taSource.source);
                                taGFX.textureScale = cCSF.csf;
                                this._gfxData.addTAGFX(cScale.scale, cCSF.csf, taSource.id, taGFX);
                            }
                            else
                            {
                                this.zipProcessError(ErrorConstants.ATLAS_NOT_FOUND + taSource.source + "' in zip", 3);
                            }
                        }
                    }
                }
            }
        }
        
        var timeline : GAFTimeline = new GAFTimeline(config);
        timeline.gafgfxData = this._gfxData;
        timeline.gafSoundData = this._soundData;
        timeline.gafAsset = asset;
        
        var _sw0_ = (ZipToGAFAssetConverter.actionWithAtlases);        

        switch (_sw0_)
        {
            case ZipToGAFAssetConverter.ACTION_LOAD_ALL_IN_GPU_MEMORY:
                timeline.loadInVideoMemory(GAFTimeline.CONTENT_ALL);
            
            case ZipToGAFAssetConverter.ACTION_LOAD_IN_GPU_MEMORY_ONLY_DEFAULT:
                timeline.loadInVideoMemory(GAFTimeline.CONTENT_DEFAULT);
        }
        
        return timeline;
    }
    
    private function getAssetId(configName : String) : String
    {
        var startIndex : Int = configName.lastIndexOf("/");
        
        if (startIndex < 0)
        {
            startIndex = 0;
        }
        else
        {
            startIndex++;
        }
        
        var endIndex : Int = configName.lastIndexOf(".");
        
        if (endIndex < 0)
        {
            endIndex = 0x7fffffff;
        }
        
        return configName.substring(startIndex, endIndex);
    }
    
    private function zipProcessError(text : String, id : Int = 0) : Void
    {
        this.onConvertError(new ErrorEvent(ErrorEvent.ERROR, false, false, text, id));
    }
    
    private function removeLoaderListeners(target : EventDispatcher, onComplete : Dynamic, onError : Dynamic) : Void
    {
        target.removeEventListener(Event.COMPLETE, onComplete);
        target.removeEventListener(IOErrorEvent.IO_ERROR, onError);
    }
    
    //--------------------------------------------------------------------------
    //
    // OVERRIDDEN METHODS
    //
    //--------------------------------------------------------------------------
    
    //--------------------------------------------------------------------------
    //
    //  EVENT HANDLERS
    //
    //--------------------------------------------------------------------------
    
    private function onParseError() : Void
    {
        this.zipProcessError(ErrorConstants.ERROR_PARSING, 1);
    }
    
    private function onConvertError(event : ErrorEvent) : Void
    {
        if (this.hasEventListener(ErrorEvent.ERROR))
        {
            this.dispatchEvent(event);
        }
        else
        {
            throw new Error(event.text);
        }
    }
    
    private function onConverted(event : Event) : Void
    {
        var configID : String = this._gafAssetsIDs[this._currentConfigIndex];
        var folderURL : String = getFolderURL(configID);
        var converter : BinGAFAssetConfigConverter = cast(event.target, BinGAFAssetConfigConverter);
        converter.removeEventListener(Event.COMPLETE, onConverted);
        converter.removeEventListener(ErrorEvent.ERROR, onConvertError);
		
        
        this._gafAssetConfigs.set(configID, converter.config);
        var sounds : Array<CSound> = converter.config.sounds;
        if (sounds != null && !this._ignoreSounds)
        {
			for (i in 0...sounds.length) 
			{
                sounds[i].source = folderURL + sounds[i].source;
                this._soundData.addSound(sounds[i], converter.config.id, this._sounds.get(sounds[i].source));
            }
        }
        
        this._currentConfigIndex++;
        
        if (this._currentConfigIndex >= this._gafAssetsIDs.length)
        {
            if (this._gafAssetsConfigURLs != null && _gafAssetsConfigURLs.length > 0)
            {
                this.findAllAtlasURLs();
            }
            else
            {
                this.createGAFTimelines();
            }
        }
        else
        {
			Timer.delay(this.convertConfig, 40);
        }
    }
    
    private function onConfigLoadComplete(event : Event) : Void
    {
        var loader : URLLoader = cast(event.target, URLLoader);
        var url : String = this._gafAssetsConfigURLs[this._gafAssetsConfigIndex];
        
        this.removeLoaderListeners(loader, onConfigLoadComplete, onConfigIOError);
        
        this._gafAssetsIDs.push(url);
        
        this._gafAssetConfigSources.set(url, loader.data);
        
        this._gafAssetsConfigIndex++;
        
        if (this._gafAssetsConfigIndex >= this._gafAssetsConfigURLs.length)
        {
            this.convertConfig();
        }
        else
        {
            this.loadConfig();
        }
    }
    
    private function onConfigIOError(event : IOErrorEvent) : Void
    {
        var url : String = this._gafAssetsConfigURLs[this._gafAssetsConfigIndex];
        this.removeLoaderListeners(cast(event.target, URLLoader), onConfigLoadComplete, onConfigIOError);
        this.zipProcessError(ErrorConstants.ERROR_LOADING + url, 5);
    }
    
    private function onSoundLoadIOError(event : IOErrorEvent) : Void
    {
        var sound : Sound = cast(event.target, Sound);
        this.removeLoaderListeners(cast(event.target, URLLoader), onSoundLoadIOError, onSoundLoadIOError);
        this.zipProcessError(ErrorConstants.ERROR_LOADING + sound.url, 6);
    }
    
    private function onTexturesReady(event : Event) : Void
    {
        this._gfxData.removeEventListener(GAFGFXData.EVENT_TYPE_TEXTURES_READY, this.onTexturesReady);
        
        this.dispatchEvent(new Event(Event.COMPLETE));
    }
    
    //--------------------------------------------------------------------------
    //
    //  GETTERS AND SETTERS
    //
    //--------------------------------------------------------------------------
    
    /**
	 * Return converted <code>GAFBundle</code>. If GAF asset file created as single animation - returns null.
	 */
    private function get_gafBundle() : GAFBundle
    {
        return this._gafBundle;
    }
    
    /**
	 * Returns the first <code>GAFTimeline</code> in a <code>GAFBundle</code>.
	 */
    @:meta(Deprecated(replacement="com.catalystapps.gaf.data.GAFBundle.getGAFTimeline()",since="5.0"))
    private function get_gafTimeline() : GAFTimeline
    {
        if (this._gafBundle != null && this._gafBundle.gafAssets.length > 0)
        {
            for (asset in this._gafBundle.gafAssets)
            {
                if (asset.timelines.length > 0)
                {
                    return asset.timelines[0];
                }
            }
        }
        return null;
    }
    
    /**
	 * Return loaded zip file as <code>FZip</code> object
	 */
    private function get_zip() : ZipReader
    {
        return this._zip;
    }
    
    /**
	 * Return zipLoader object
	 */
    private function get_zipLoader() : Map<String, ZipEntry>
    {
        return this._zipLoader;
    }
    
    /**
	 * The id of the converter.
	 * If it is not empty <code>ZipToGAFAssetConverter</code> sets the <code>name</code> of produced bundle equal to this id.
	 */
    private function get_id() : String
    {
        return this._id;
    }
    
    private function set_id(value : String) : String
    {
        this._id = value;
        return value;
    }
    
    private function get_parseConfigAsync() : Bool
    {
        return this._parseConfigAsync;
    }
    
    /**
	 * Indicates whether to convert *.gaf config file asynchronously.
	 * If <code>true</code> - conversion is divided by chunk of 20 ms (may be up to
	 * 2 times slower than synchronous conversion, but conversion won't freeze the interface).
	 * If <code>false</code> - conversion goes within one stack (up to
	 * 2 times faster than async conversion, but conversion freezes the interface).
	 */
    private function set_parseConfigAsync(parseConfigAsync : Bool) : Bool
    {
        this._parseConfigAsync = parseConfigAsync;
        return parseConfigAsync;
    }
    
    /**
	 * Prevents loading of sounds
	 */
    private function set_ignoreSounds(ignoreSounds : Bool) : Bool
    {
        this._ignoreSounds = ignoreSounds;
        return ignoreSounds;
    }
	
	inline
	function getBytes(entry:ZipEntry):ByteArray 
	{
		var data:ByteArray = entry.data.getData();
		if(entry.compressed)
			data.uncompress(CompressionAlgorithm.DEFLATE);
		
		return data;
	}
}
