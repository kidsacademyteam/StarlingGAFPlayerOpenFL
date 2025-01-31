package com.catalystapps.gaf.display;

import com.catalystapps.gaf.data.GAF;
import com.catalystapps.gaf.data.GAFAsset;
import com.catalystapps.gaf.data.GAFDebugInformation;
import com.catalystapps.gaf.data.GAFTimeline;
import com.catalystapps.gaf.data.GAFTimelineConfig;
import com.catalystapps.gaf.data.config.CAnimationFrame;
import com.catalystapps.gaf.data.config.CAnimationFrameInstance;
import com.catalystapps.gaf.data.config.CAnimationObject;
import com.catalystapps.gaf.data.config.CAnimationSequence;
import com.catalystapps.gaf.data.config.CFilter;
import com.catalystapps.gaf.data.config.CFrameAction;
import com.catalystapps.gaf.data.config.CSound;
import com.catalystapps.gaf.data.config.CTextFieldObject;
import com.catalystapps.gaf.data.config.CTextureAtlas;
import com.catalystapps.gaf.display.GAFTextField;
import com.catalystapps.gaf.filter.GAFFilterChain;
import com.catalystapps.gaf.filter.masks.GAFStencilMaskStyle;
import com.catalystapps.gaf.utils.DebugUtility;
import flash.errors.ArgumentError;
import flash.errors.Error;
import flash.errors.IllegalOperationError;
import flash.events.ErrorEvent;
import flash.geom.Matrix;
import flash.geom.Point;
import flash.geom.Rectangle;
import openfl.Vector;
import starling.animation.IAnimatable;
import starling.core.Starling;
import starling.display.DisplayObject;
import starling.display.DisplayObjectContainer;
import starling.display.Quad;
import starling.display.MeshBatch;
import starling.display.Sprite;
import starling.events.Event;
import starling.rendering.Painter;
import starling.textures.TextureSmoothing;

/*
// Dispatched when playhead reached first frame of sequence
@:meta(Event(name="typeSequenceStart",type="starling.events.Event"))

// Dispatched when playhead reached end frame of sequence
@:meta(Event(name="typeSequenceEnd",type="starling.events.Event"))

// Dispatched whenever the movie has displayed its last frame.
@:meta(Event(name="complete",type="starling.events.Event"))
*/

/**
 * GAFMovieClip represents animation display object that is ready to be used in Starling display list. It has
 * all controls for animation familiar from standard MovieClip (<code>play</code>, <code>stop</code>, <code>gotoAndPlay,</code> etc.)
 * and some more like <code>loop</code>, <code>nPlay</code>, <code>setSequence</code> that helps manage playback
 */
//class GAFMovieClip extends Sprite implements IAnimatable implements IGAFDisplayObject implements IMaxSize implements Dynamic<String> 
class GAFMovieClip extends Sprite implements IAnimatable implements IGAFDisplayObject implements IMaxSize
{
    public var currentSequence(get, never) : String;
    public var currentFrame(get, never) : Int;
    public var totalFrames(get, never) : Int;
    public var inPlay(get, never) : Bool;
    public var loop(get, set) : Bool;
    public var smoothing(get, set) : String;
    public var useClipping(get, set) : Bool;
    public var maxSize(get, set) : Point;
    public var fps(get, set) : Float;
    public var reverse(get, set) : Bool;
    public var skipFrames(get, set) : Bool;
    public var pivotMatrix(get, never) : Matrix;

    public static inline var EVENT_TYPE_SEQUENCE_START : String = "typeSequenceStart";
    public static inline var EVENT_TYPE_SEQUENCE_END : String = "typeSequenceEnd";
    
    private static var HELPER_MATRIX : Matrix = new Matrix();
    //--------------------------------------------------------------------------
    //
    //  PUBLIC VARIABLES
    //
    //--------------------------------------------------------------------------
    
    //--------------------------------------------------------------------------
    //
    //  PRIVATE VARIABLES
    //
    //--------------------------------------------------------------------------
    
    private var _smoothing : String = TextureSmoothing.BILINEAR;
    
    private var _displayObjectsDictionary : Map<String, DisplayObject> = null;
    private var _stencilMasksDictionary : Map<String, DisplayObject> = null;
    private var _displayObjectsVector : Array<IGAFDisplayObject> = null;
    private var _imagesVector : Array<IGAFImage> = null;
    private var _mcVector : Array<GAFMovieClip> = null;
    
    private var _playingSequence : CAnimationSequence = null;
    private var _timelineBounds : Rectangle = null;
    private var _maxSize : Point = null;
    private var _boundsAndPivot : MeshBatch = null;
    private var _config : GAFTimelineConfig = null;
    private var _gafTimeline : GAFTimeline = null;
    
    private var _loop : Bool = true;
    private var _skipFrames : Bool = true;
    private var _reset : Bool = false;
    private var _masked : Bool = false;
    private var _inPlay : Bool = false;
    private var _hidden : Bool = false;
    private var _reverse : Bool = false;
    private var _started : Bool = false;
    private var _disposed : Bool = false;
    private var _hasFilter : Bool = false;
    private var _useClipping : Bool = false;
    private var _alphaLessMax : Bool = false;
    private var _addToJuggler : Bool = false;
    
    private var _scale : Float = Math.NaN;
    private var _contentScaleFactor : Float = Math.NaN;
    private var _currentTime : Float = 0;
    // Hold the current time spent animating
    private var _lastFrameTime : Float = 0;
    private var _frameDuration : Float = Math.NaN;
    
    private var _nextFrame : Int = 0;
    private var _startFrame : Int = 0;
    private var _finalFrame : Int = 0;
    private var _currentFrame : Int = 0;
    private var _totalFrames : Int = 0;
    
    private var _filterChain : GAFFilterChain = null;
    private var _filterConfig : CFilter = null;
    private var _filterScale : Float = Math.NaN;
    
    private var _pivotChanged : Bool = false;
    
    /** @private */
	@:allow(com.catalystapps.gaf)
    private var __debugOriginalAlpha : Float = Math.NaN;
    
    private var _orientationChanged : Bool = false;
    
    private var _stencilMaskStyle : GAFStencilMaskStyle = null;
	
	
	//instead of Dynamics hold DisplayObject here, take with get()
	private var props : Map<String, DisplayObject> = new Map();
    
    // --------------------------------------------------------------------------
    //
    //  CONSTRUCTOR
    //
    //--------------------------------------------------------------------------
    
    /**
	 * Creates a new GAFMovieClip instance.
	 *
	 * @param gafTimeline <code>GAFTimeline</code> from what <code>GAFMovieClip</code> will be created
	 * @param fps defines the frame rate of the movie clip. If not set - the stage config frame rate will be used instead.
	 * @param addToJuggler if <code>true - GAFMovieClip</code> will be added to <code>Starling.juggler</code>
	 * and removed automatically on <code>dispose</code>
	 */
    public function new(gafTimeline : GAFTimeline, fps : Int = -1, addToJuggler : Bool = true)
    {
        super();
        this._gafTimeline = gafTimeline;
        this._config = gafTimeline.config;
        this._scale = gafTimeline.scale;
        this._contentScaleFactor = gafTimeline.contentScaleFactor;
        this._addToJuggler = addToJuggler;
        
        this.initialize(gafTimeline.textureAtlas, gafTimeline.gafAsset);
        
        if (this._config.bounds != null)
        {
            this._timelineBounds = this._config.bounds.clone();
        }
        if (fps > 0)
        {
            this.fps = fps;
        }
        
        this.draw();
    }
    
    //--------------------------------------------------------------------------
    //
    //  PUBLIC METHODS
    //
    //--------------------------------------------------------------------------
    
    /** @private
	 * Returns the child display object that exists with the specified ID. Use to obtain animation's parts
	 *
	 * @param id Child ID
	 * @return The child display object with the specified ID
	 */
    public function getChildByID(id : String) : DisplayObject
    {
        return this._displayObjectsDictionary[id];
    }
    
    /** @private
	 * Returns the mask display object that exists with the specified ID. Use to obtain animation's masks
	 *
	 * @param id Mask ID
	 * @return The mask display object with the specified ID
	 */
    public function getMaskByID(id : String) : DisplayObject
    {
        return this._stencilMasksDictionary[id];
    }
    
    /**
	 * Shows mask display object that exists with the specified ID. Used for debug purposes only!
	 *
	 * @param id Mask ID
	 */
    public function showMaskByID(id : String) : Void
    {
		/*
        var maskObject : IGAFDisplayObject = this._displayObjectsDictionary[id];
        var maskAsDisplayObject : DisplayObject = cast(maskObject, DisplayObject);
        var stencilMaskObject : DisplayObject = this._stencilMasksDictionary[id];
		/*/
        var maskAsDisplayObject : DisplayObject = this._displayObjectsDictionary[id];
        ///var maskObject : IGAFDisplayObject = cast(this._displayObjectsDictionary[id], IGAFDisplayObject);
        var stencilMaskObject : DisplayObject = this._stencilMasksDictionary[id];
		//*/
		
        //if (maskObject != null && stencilMaskObject != null)
        if (maskAsDisplayObject != null && stencilMaskObject != null)
        {
            maskAsDisplayObject.mask = stencilMaskObject;
            this.addChild(stencilMaskObject);
            this.addChild(maskAsDisplayObject);
        }
        else
        {
            trace("WARNING: mask object is missing. It might be disposed.");
        }
    }
    
    /**
	 * Hides mask display object that previously has been shown using <code>showMaskByID</code> method.
	 * Used for debug purposes only!
	 *
	 * @param id Mask ID
	 */
    public function hideMaskByID(id : String) : Void
    {
		/*
        var maskObject : IGAFDisplayObject = cast(this._displayObjectsDictionary[id], IGAFDisplayObject);
        var maskAsDisplayObject : DisplayObject = cast(maskObject, DisplayObject);
        var stencilMaskObject : DisplayObject = this._stencilMasksDictionary[id];
		*/
        var maskAsDisplayObject : DisplayObject = this._displayObjectsDictionary[id];
        ///var maskObject : IGAFDisplayObject = cast(maskAsDisplayObject, IGAFDisplayObject);
        var stencilMaskObject : DisplayObject = this._stencilMasksDictionary[id];
		
        if (stencilMaskObject != null)
        {
            if (stencilMaskObject.parent == this)
            {
                stencilMaskObject.parent.mask = null;
                this.removeChild(stencilMaskObject);
                this.removeChild(maskAsDisplayObject);
            }
        }
        else
        {
            trace("WARNING: mask object is missing. It might be disposed.");
        }
    }
    
    /**
	 * Clear playing sequence. If animation already in play just continue playing without sequence limitation
	 */
    public function clearSequence() : Void
    {
        this._playingSequence = null;
    }
    
    /**
	 * Returns id of the sequence where animation is right now. If there is no sequences - returns <code>null</code>.
	 *
	 * @return id of the sequence
	 */
    private function get_currentSequence() : String
    {
        var sequence : CAnimationSequence = this._config.animationSequences.getSequenceByFrame(this.currentFrame);
        if (sequence != null)
        {
            return sequence.id;
        }
        return null;
    }
    
    /**
	 * Set sequence to play
	 *
	 * @param id Sequence ID
	 * @param play Play or not immediately. <code>true</code> - starts playing from sequence start frame. <code>false</code> - go to sequence start frame and stop
	 * @return sequence to play
	 */
    public function setSequence(id : String, play : Bool = true) : CAnimationSequence
    {
        this._playingSequence = this._config.animationSequences.getSequenceByID(id);
        
        if (this._playingSequence != null)
        {
            var startFrame : Int = (this._reverse) ? this._playingSequence.endFrameNo - 1 : this._playingSequence.startFrameNo;
            if (play)
            {
                this.gotoAndPlay(startFrame);
            }
            else
            {
                this.gotoAndStop(startFrame);
            }
        }
        
        return this._playingSequence;
    }
    
    /**
	 * Moves the playhead in the timeline of the movie clip <code>play()</code> or <code>play(false)</code>.
	 * Or moves the playhead in the timeline of the movie clip and all child movie clips <code>play(true)</code>.
	 * Use <code>play(true)</code> in case when animation contain nested timelines for correct playback right after
	 * initialization (like you see in the original swf file).
	 * @param applyToAllChildren Specifies whether playhead should be moved in the timeline of the movie clip
	 * (<code>false</code>) or also in the timelines of all child movie clips (<code>true</code>).
	 */
    public function play(applyToAllChildren : Bool = false) : Void
    {
        this._started = true;
        
        if (applyToAllChildren)
        {
            var i : Int = this._mcVector.length;
            while (i-- > 0)
            {
                this._mcVector[i]._started = true;
            }
        }
        
        this._play(applyToAllChildren, true);
    }
    
    /**
	 * Stops the playhead in the movie clip <code>stop()</code> or <code>stop(false)</code>.
	 * Or stops the playhead in the movie clip and in all child movie clips <code>stop(true)</code>.
	 * Use <code>stop(true)</code> in case when animation contain nested timelines for full stop the
	 * playhead in the movie clip and in all child movie clips.
	 * @param applyToAllChildren Specifies whether playhead should be stopped in the timeline of the
	 * movie clip (<code>false</code>) or also in the timelines of all child movie clips (<code>true</code>)
	 */
    public function stop(applyToAllChildren : Bool = false) : Void
    {
        this._started = false;
        
        if (applyToAllChildren)
        {
            var i : Int = this._mcVector.length;
            while (i-- > 0)
            {
                this._mcVector[i]._started = false;
            }
        }
        
        this._stop(applyToAllChildren, true);
    }
    
    /**
	 * Brings the playhead to the specified frame of the movie clip and stops it there. First frame is "1"
	 *
	 * @param frame A number representing the frame number, or a string representing the label of the frame, to which the playhead is sent.
	 */
    public function gotoAndStop(frame : Dynamic) : Void
    {
        this.checkAndSetCurrentFrame(frame);
        
        this.stop();
    }
    
    /**
	 * Starts playing animation at the specified frame. First frame is "1"
	 *
	 * @param frame A number representing the frame number, or a string representing the label of the frame, to which the playhead is sent.
	 */
    public function gotoAndPlay(frame : Dynamic) : Void
    {
        this.checkAndSetCurrentFrame(frame);
        
        this.play();
    }
    
    /**
	 * Set the <code>loop</code> value to the GAFMovieClip instance and for the all children.
	 */
    public function loopAll(loop : Bool) : Void
    {
        this.loop = loop;
        
        var i : Int = this._mcVector.length;
        while (i-- > 0)
        {
            this._mcVector[i].loop = loop;
        }
    }
    
    /** @private
	 * Advances all objects by a certain time (in seconds).
	 * @see starling.animation.IAnimatable
	 */
    public function advanceTime(passedTime : Float) : Void
    {
        if (this._disposed)
        {
            trace("WARNING: GAFMovieClip is disposed but is not removed from the Juggler");
            return;
        }
        else if (this._config.disposed)
        {
            this.dispose();
            return;
        }
        
        if (this._inPlay && this._frameDuration != Math.POSITIVE_INFINITY)
        {
            this._currentTime += passedTime;
            
            var framesToPlay : Int = Std.int((this._currentTime - this._lastFrameTime) / this._frameDuration);
            if (this._skipFrames)
			{
				//here we skip the drawing of all frames to be played right now, but the last one
                for (i in 0...framesToPlay)
                {
                    if (this._inPlay)
                    {
                        this.changeCurrentFrame((i + 1) != framesToPlay);
                    }
                    else //if a playback was interrupted by some action or an event
                    {
                        
                        if (!this._disposed)
                        {
                            this.draw();
                        }
                        break;
                    }
                }
            }
            else if (framesToPlay > 0)
            {
                this.changeCurrentFrame(false);
            }
        }
        if (this._mcVector != null)
        {
			for (i in 0...this._mcVector.length) 
			{
                this._mcVector[i].advanceTime(passedTime);
            }
        }
    }
    
    /** Shows bounds of a whole animation with a pivot point.
	 * Used for debug purposes.
	 */
    public function showBounds(value : Bool) : Void
    {
        if (this._config.bounds != null)
        {
            if (this._boundsAndPivot == null)
            {
                this._boundsAndPivot = new MeshBatch();
                this.updateBounds(this._config.bounds);
            }
            
            if (value)
            {
                this.addChild(this._boundsAndPivot);
            }
            else
            {
                this.removeChild(this._boundsAndPivot);
            }
        }
    }
    
    /**
	 * Disposes GAFMovieClip with config and all textures that was loaded with gaf file.
	 * Do not call this method if you have another GAFMovieClips that made from the same config
	 * or even loaded from the same gaf file.
	 */
    @:meta(Deprecated(replacement="com.catalystapps.gaf.data.GAFBundle.dispose()",since="5.0"))
    public function disposeWithTextures() : Void
    {
        this._gafTimeline.unloadFromVideoMemory();
        this._gafTimeline = null;
        this._config.dispose();
        this.dispose();
    }
    
    /** @private */
    public function setFilterConfig(value : CFilter, scale : Float = 1) : Void
    {
        if (!Starling.current.contextValid)
        {
            return;
        }
        
        if (this._filterConfig != value || this._filterScale != scale)
        {
            if (value != null)
            {
                this._filterConfig = value;
                this._filterScale = scale;
                
                if (this._filterChain != null)
                {
                    _filterChain.dispose();
                }
                else
                {
                    _filterChain = new GAFFilterChain();
                }
                
                _filterChain.setFilterData(_filterConfig);
                this.filter = _filterChain;
            }
            else
            {
                if (this.filter != null)
                {
                    this.filter.dispose();
                    this.filter = null;
                }
                
                this._filterChain = null;
                this._filterConfig = null;
                this._filterScale = Math.NaN;
            }
        }
    }
    
    /** @private */
    public function invalidateOrientation() : Void
    {
        this._orientationChanged = true;
    }
    
    /**
	 * Creates a new instance of GAFMovieClip.
	 */
    public function copy() : GAFMovieClip
    {
        return new GAFMovieClip(this._gafTimeline, Std.int(this.fps), this._addToJuggler);
    }
    
    //--------------------------------------------------------------------------
    //
    //  PRIVATE METHODS
    //
    // --------------------------------------------------------------------------
    
    private function _gotoAndStop(frame : Dynamic) : Void
    {
        this.checkAndSetCurrentFrame(frame);
        
        this._stop();
    }
    
    private function _play(applyToAllChildren : Bool = false, calledByUser : Bool = false) : Void
    {
        if (this._inPlay && !applyToAllChildren)
        {
            return;
        }
        
        var i : Int;
        var l : Int;
        
        if (this._totalFrames > 1)
        {
            this._inPlay = true;
        }
		
        if (applyToAllChildren
            && this._config.animationConfigFrames.frames.length > 0)
        {
            var frameConfig : CAnimationFrame = this._config.animationConfigFrames.frames[this._currentFrame];
            if (frameConfig.actions != null)
            {
                var action : CFrameAction;
				l = frameConfig.actions.length;
                for (i in 0...l)
                {
                    action = frameConfig.actions[i];
                    if (action.type == CFrameAction.STOP 
					|| (action.type == CFrameAction.GOTO_AND_STOP 
					&& Std.parseInt(action.params[0]) == this.currentFrame))
                    {
                        this._inPlay = false;
                        return;
                    }
                }
            }
            
            var child : DisplayObjectContainer;
            var childMC : GAFMovieClip;
            
			l = this.numChildren;
            for (i in 0...l)
            {
                //child = try cast(this.getChildAt(i), DisplayObjectContainer) catch(e:Dynamic) null;
				if (Std.isOfType(this.getChildAt(i), DisplayObjectContainer))
				{
					child = cast(this.getChildAt(i), DisplayObjectContainer);
					if (Std.isOfType(child, GAFMovieClip))
					{
						childMC = cast(child, GAFMovieClip);
						if (calledByUser)
						{
							childMC.play(true);
						}
						else
						{
							childMC._play(true);
						}
					}
				}
            }
        }
        
        this.runActions();
        
        this._reset = false;
    }
    
    private function _stop(applyToAllChildren : Bool = false, calledByUser : Bool = false) : Void
    {
        this._inPlay = false;
        
        if (applyToAllChildren
            && this._config.animationConfigFrames.frames.length > 0)
        {
            var child : DisplayObjectContainer;
            var childMC : GAFMovieClip;
            
            for (i in 0 ... this.numChildren)
            {
                //child = try cast(this.getChildAt(i), DisplayObjectContainer) catch(e:Dynamic) null;
				if (Std.isOfType(this.getChildAt(i), DisplayObjectContainer))
				{
					child = cast(this.getChildAt(i), DisplayObjectContainer);
					if (Std.isOfType(child, GAFMovieClip))
					{
						//childMC = try cast(child, GAFMovieClip) catch(e:Dynamic) null;
						childMC = cast(child, GAFMovieClip);
						if (calledByUser)
						{
							childMC.stop(true);
						}
						else
						{
							childMC._stop(true);
						}
					}
				}
            }
        }
    }
    
    private function checkPlaybackEvents() : Void
    {
        var sequence : CAnimationSequence;
        if (this.hasEventListener(EVENT_TYPE_SEQUENCE_START))
        {
            sequence = this._config.animationSequences.getSequenceStart(this._currentFrame + 1);
            if (sequence != null)
            {
                this.dispatchEventWith(EVENT_TYPE_SEQUENCE_START, false, sequence);
            }
        }
        if (this.hasEventListener(EVENT_TYPE_SEQUENCE_END))
        {
            sequence = this._config.animationSequences.getSequenceEnd(this._currentFrame + 1);
            if (sequence != null)
            {
                this.dispatchEventWith(EVENT_TYPE_SEQUENCE_END, false, sequence);
            }
        }
        if (this.hasEventListener(Event.COMPLETE))
        {
            if (this._currentFrame == this._finalFrame)
            {
                this.dispatchEventWith(Event.COMPLETE);
            }
        }
    }
    
    private function runActions() : Void
    {
        if (this._config.animationConfigFrames.frames.length == 0)
        {
            return;
        }
		
        var i : Int;
        var l : Int;
        var actions : Array<CFrameAction> = this._config.animationConfigFrames.frames[this._currentFrame].actions;
        if (actions != null)
        {
            var action : CFrameAction;
			l = actions.length;
            for (i in 0...l)
            {
                action = actions[i];
				
                var _sw1_ = (action.type);                
                switch (_sw1_)
                {
                    case CFrameAction.STOP:
                        this.stop();
                    case CFrameAction.PLAY:
                        this.play();
                    case CFrameAction.GOTO_AND_STOP:
                        this.gotoAndStop(action.params[0]);
                    case CFrameAction.GOTO_AND_PLAY:
                        this.gotoAndPlay(action.params[0]);
                    case CFrameAction.DISPATCH_EVENT:
                        var actionType : String = action.params[0];
                        if (this.hasEventListener(actionType))
                        {
                            var _sw2_ = (action.params.length);
							var data:Dynamic = null;
							var bubbles:Bool = false;
							
							if (_sw2_ >= 4)
							{
								data = action.params[3];
							}
							if (_sw2_ >= 3)
							{
								// cancelable param is not used
							}
							if (_sw2_ >= 2)
							{
								//bubbles = cast(action.params[1], Bool);
								bubbles = (action.params[1] != null && action.params[1] != "");
							}
							
                            this.dispatchEventWith(actionType, bubbles, data);
                        }
                        if (actionType == CSound.GAF_PLAY_SOUND && GAF.autoPlaySounds)
                        {
                            this._gafTimeline.startSound(this.currentFrame);
                        }
                }
            }
        }
    }
    
    private function checkAndSetCurrentFrame(_frame : Dynamic) : Void
    {
		var frame:Int = 1;
		/*
        if (as3hx.Compat.parseInt(_frame) > 0)
        {
			frame = as3hx.Compat.parseInt(_frame);
			
            if (frame > this._totalFrames)
            {
                frame = this._totalFrames;
            }
        }
		*/
		if (Std.isOfType(_frame, Int) && ((frame = _frame) > 0))
		{
			if (frame > this._totalFrames)
			{
				frame = this._totalFrames;
			}
		}
        else if (Std.isOfType(_frame, String))
        {
            var label : String = _frame;
            frame = this._config.animationSequences.getStartFrameNo(label);
            
            if (frame == 0)
            {
                throw new ArgumentError("Frame label " + label + " not found");
            }
        }
        else
        {
            frame = 1;
        }
        
        if (this._playingSequence != null && !this._playingSequence.isSequenceFrame(frame))
        {
            this._playingSequence = null;
        }
        
        if (this._currentFrame != frame - 1)
        {
            this._currentFrame = frame - 1;
            this.runActions();
            //actions may interrupt playback and lead to content disposition
            if (!this._disposed)
            {
                this.draw();
            }
        }
    }
    
    private function clearDisplayList() : Void
    {
        this.removeChildren();
    }
    
    private function draw() : Void
    {
        var i : Int;
        var l : Int;
        
        if (this._config.debugRegions != null)
		{
			// Non optimized way when there are debug regions
            this.clearDisplayList();
        }
        else
        {
			// Just hide the children to avoid dispatching a lot of events and alloc temporary arrays
			l = this._displayObjectsVector.length;
            for (i in 0...l)
            {
                this._displayObjectsVector[i].alpha = 0;
            }
            
			l = this._mcVector.length;
            for (i in 0...l)
            {
                this._mcVector[i]._hidden = true;
            }
        }
        
        var frames : Array<CAnimationFrame> = this._config.animationConfigFrames.frames;
        if (frames.length > this._currentFrame)
        {
            var mc : GAFMovieClip;
            var objectPivotMatrix : Matrix;
            var displayObject : IGAFDisplayObject;
            var instance : CAnimationFrameInstance;
            var stencilMaskObject : DisplayObject = null;
            
            var animationObjectsDictionary : Map<String, CAnimationObject> = this._config.animationObjects.animationObjectsDictionary;
            var frameConfig : CAnimationFrame = frames[this._currentFrame];
            var instances : Array<CAnimationFrameInstance> = frameConfig.instances;
            l = instances.length;
            i = 0;
            while (i < l)
            {
                instance = instances[i++];
                
                displayObject = cast(this._displayObjectsDictionary[instance.id], IGAFDisplayObject);
                if (displayObject != null)
                {
                    objectPivotMatrix = getTransformMatrix(displayObject, HELPER_MATRIX);
					
					if (Std.isOfType(displayObject, GAFMovieClip))
					{
						mc = cast(displayObject, GAFMovieClip);
					}
					else
					{
						mc = null;
					}
					
                    if (mc != null)
                    {
                        if (instance.alpha < 0)
                        {
                            mc.reset();
                        }
                        else if (mc._reset && mc._started)
                        {
                            mc._play(true);
                        }
                        mc._hidden = false;
                    }
                    
                    if (instance.alpha <= 0)
                    {
                        continue;
                    }
                    displayObject.alpha = instance.alpha;
                    
                    //if display object is not a mask
                    if (!animationObjectsDictionary[instance.id].mask) 
					{
						//if display object is under mask
                        if (instance.maskID != null && instance.maskID != "")
                        {
                            this.renderDebug(mc, instance, true);
                            
                            stencilMaskObject = this._stencilMasksDictionary[instance.maskID];
                            if (stencilMaskObject != null)
                            {
                                _stencilMaskStyle = new GAFStencilMaskStyle();
                                cast(stencilMaskObject, GAFImage).style = _stencilMaskStyle;
                                
                                instance.applyTransformMatrix(displayObject.transformationMatrix, objectPivotMatrix, this._scale);
                                displayObject.invalidateOrientation();
                                
                                cast(displayObject, DisplayObject).mask = stencilMaskObject;
                                
                                this.addChild(stencilMaskObject);
                                this.addChild(cast(displayObject, DisplayObject));
                                
                                _stencilMaskStyle.threshold = 1;
                            }
                        }
                        else //if display object is not masked
                        {
							this.renderDebug(mc, instance, this._masked);
							
							instance.applyTransformMatrix(displayObject.transformationMatrix, objectPivotMatrix, this._scale);
							displayObject.invalidateOrientation();
							displayObject.setFilterConfig(instance.filter, this._scale);
							
							//this.addChild(try cast(displayObject, DisplayObject) catch(e:Dynamic) null);
							this.addChild(cast(displayObject, DisplayObject));
                        }
                        
                        if (mc != null && mc._started)
                        {
                            mc._play(true);
                        }
                        
                        if (DebugUtility.RENDERING_DEBUG && Std.isOfType(displayObject, IGAFDebug))
                        {
                            var colors : Array<Int> = DebugUtility.getRenderingDifficultyColor(
                                    instance, this._alphaLessMax, this._masked, this._hasFilter
								);
                            cast(displayObject, IGAFDebug).debugColors = colors;
                        }
                    }
                    else
                    {
                        var maskObject : IGAFDisplayObject = cast(this._displayObjectsDictionary[instance.id], IGAFDisplayObject);
                        if (maskObject != null)
                        {
                            var maskInstance : CAnimationFrameInstance = frameConfig.getInstanceByID(instance.id);
                            if (maskInstance != null)
                            {
                                getTransformMatrix(maskObject, HELPER_MATRIX);
                                maskInstance.applyTransformMatrix(maskObject.transformationMatrix, HELPER_MATRIX, this._scale);
                                maskObject.invalidateOrientation();
                            }
                            else
                            {
                                throw new Error("Unable to find mask with ID " + instance.id);
                            }
                            
                            //mc = try cast(maskObject, GAFMovieClip) catch(e:Dynamic) null;
                            if (Std.isOfType(maskObject, GAFMovieClip))
							{
								mc = cast(maskObject, GAFMovieClip);
							}
							else
							{
								mc = null;
							}
							
                            if (mc != null && mc._started)
                            {
                                mc._play(true);
                            }
                        }
                    }
                }
            }
        }
        
        if (this._config.debugRegions != null)
        {
            this.addDebugRegions();
        }
        
        this.checkPlaybackEvents();
    }
    
    private function renderDebug(mc : GAFMovieClip, instance : CAnimationFrameInstance, masked : Bool) : Void
    {
        if (DebugUtility.RENDERING_DEBUG && mc != null)
        {
            var hasFilter : Bool = (instance.filter != null) || this._hasFilter;
            var alphaLessMax : Bool = (instance.alpha < GAF.maxAlpha) || this._alphaLessMax;
            
            var changed : Bool = false;
            if (mc._alphaLessMax != alphaLessMax)
            {
                mc._alphaLessMax = alphaLessMax;
                changed = true;
            }
            if (mc._masked != masked)
            {
                mc._masked = masked;
                changed = true;
            }
            if (mc._hasFilter != hasFilter)
            {
                mc._hasFilter = hasFilter;
                changed = true;
            }
            if (changed)
            {
                mc.draw();
            }
        }
    }
    
    private function addDebugRegions() : Void
    {
        var debugView : Quad = null;
        for (debugRegion in this._config.debugRegions)
        {
            var _sw3_ = (debugRegion.type);            
			
            switch (_sw3_)
            {
                case GAFDebugInformation.TYPE_POINT:
                    debugView = new Quad(4, 4, debugRegion.color);
                    debugView.x = debugRegion.point.x - 2;
                    debugView.y = debugRegion.point.y - 2;
                    debugView.alpha = debugRegion.alpha;
                case GAFDebugInformation.TYPE_RECT:
                    debugView = new Quad(debugRegion.rect.width, debugRegion.rect.height, debugRegion.color);
                    debugView.x = debugRegion.rect.x;
                    debugView.y = debugRegion.rect.y;
                    debugView.alpha = debugRegion.alpha;
            }
            
            this.addChild(debugView);
        }
    }
    
    private function reset() : Void
    {
        this._gotoAndStop(((this._reverse) ? this._finalFrame : this._startFrame) + 1);
        this._reset = true;
        this._currentTime = 0;
        this._lastFrameTime = 0;
        
        var i : Int = this._mcVector.length;
        while (i-- > 0)
        {
            this._mcVector[i].reset();
        }
    }
    
    private function initialize(textureAtlas : CTextureAtlas, gafAsset : GAFAsset) : Void
    {
        this._displayObjectsDictionary = new Map();
        this._stencilMasksDictionary = new Map();
        this._displayObjectsVector = [];
        this._imagesVector = [];
        this._mcVector = [];
        
        this._currentFrame = 0;
        this._totalFrames = this._config.framesCount;
        this.fps = (this._config.stageConfig != null) ? this._config.stageConfig.fps : Starling.current.nativeStage.frameRate;
        
        var animationObjectsDictionary : Map<String, CAnimationObject> = this._config.animationObjects.animationObjectsDictionary;
        
        var displayObject : DisplayObject = null;
        for (animationObjectConfig in animationObjectsDictionary)
        {
            var _sw4_ = (animationObjectConfig.type);            

            switch (_sw4_)
            {
                case CAnimationObject.TYPE_TEXTURE:
                    var texture : IGAFTexture = textureAtlas.getTexture(animationObjectConfig.regionID);
                    if (Std.isOfType(texture, GAFScale9Texture) && !animationObjectConfig.mask) // GAFScale9Image doesn't work as mask
					{
                        displayObject = new GAFScale9Image(cast(texture, GAFScale9Texture));
                    }
                    else
                    {
                        displayObject = new GAFImage(texture);
                        cast(displayObject, GAFImage).textureSmoothing = this._smoothing;
                    }
					
                case CAnimationObject.TYPE_TEXTFIELD:
                    var tfObj : CTextFieldObject = this._config.textFields.textFieldObjectsDictionary[animationObjectConfig.regionID];
                    displayObject = new GAFTextField(tfObj, this._scale, this._contentScaleFactor);
					
                case CAnimationObject.TYPE_TIMELINE:
                    var timeline : GAFTimeline = gafAsset.getGAFTimelineByID(animationObjectConfig.regionID);
                    displayObject = new GAFMovieClip(timeline, Std.int(this.fps), false);
            }
            
            if (animationObjectConfig.maxSize != null && Std.isOfType(displayObject, IMaxSize))
            {
                var maxSize : Point = new Point(
                animationObjectConfig.maxSize.x * this._scale, 
                animationObjectConfig.maxSize.y * this._scale);
                cast(displayObject, IMaxSize).maxSize = maxSize;
            }
            
            this.addDisplayObject(animationObjectConfig.instanceID, displayObject);
            if (animationObjectConfig.mask)
            {
                this.addDisplayObject(animationObjectConfig.instanceID, displayObject, true);
            }
            
            if (this._config.namedParts != null)
            {
                var instanceName : String = this._config.namedParts.get(animationObjectConfig.instanceID);
                //if (instanceName != null && Reflect.field(this, instanceName) == null)
                if (instanceName != null && !props.exists(instanceName))
                {
                    //Reflect.setField(this, this._config.namedParts.get(animationObjectConfig.instanceID), displayObject);
					props.set(instanceName, displayObject);
                    displayObject.name = instanceName;
                }
            }
        }
        
        if (this._addToJuggler)
        {
            Starling.current.juggler.add(this);
        }
    }
    
    private function addDisplayObject(id : String, displayObject : DisplayObject, asMask : Bool = false) : Void
    {
        if (asMask)
        {
            this._stencilMasksDictionary[id] = displayObject;
        }
        else
        {
            this._displayObjectsDictionary.set(id, displayObject);
            //this._displayObjectsVector[_displayObjectsVector.length] = try cast(displayObject, IGAFDisplayObject) catch(e:Dynamic) null;
            this._displayObjectsVector[_displayObjectsVector.length] = cast(displayObject, IGAFDisplayObject);
            if (Std.isOfType(displayObject, IGAFImage))
            {
                //this._imagesVector[_imagesVector.length] = try cast(displayObject, IGAFImage) catch(e:Dynamic) null;
                this._imagesVector[_imagesVector.length] = cast(displayObject, IGAFImage);
            }
            else if (Std.isOfType(displayObject, GAFMovieClip))
            {
                //this._mcVector[_mcVector.length] = try cast(displayObject, GAFMovieClip) catch(e:Dynamic) null;
                this._mcVector[_mcVector.length] = cast(displayObject, GAFMovieClip);
            }
        }
    }
    
    private function updateBounds(bounds : Rectangle) : Void
    {
        this._boundsAndPivot.clear();
		
		var quad : Quad = null;
        //bounds
        if (bounds.width > 0 && bounds.height > 0)
        {
            quad = new Quad(bounds.width * this._scale, 2, 0xff0000);
            quad.x = bounds.x * this._scale;
            quad.y = bounds.y * this._scale;
            this._boundsAndPivot.addMesh(quad);
            quad = new Quad(bounds.width * this._scale, 2, 0xff0000);
            quad.x = bounds.x * this._scale;
            quad.y = bounds.bottom * this._scale - 2;
            this._boundsAndPivot.addMesh(quad);
            quad = new Quad(2, bounds.height * this._scale, 0xff0000);
            quad.x = bounds.x * this._scale;
            quad.y = bounds.y * this._scale;
            this._boundsAndPivot.addMesh(quad);
            quad = new Quad(2, bounds.height * this._scale, 0xff0000);
            quad.x = bounds.right * this._scale - 2;
            quad.y = bounds.y * this._scale;
            this._boundsAndPivot.addMesh(quad);
        }
        //pivot point
        quad = new Quad(5, 5, 0xff0000);
        this._boundsAndPivot.addMesh(quad);
    }
    
    /** @private */
	@:allow(com.catalystapps.gaf)
    private function __debugHighlight() : Void
    {
        if (Math.isNaN(this.__debugOriginalAlpha))
        {
            this.__debugOriginalAlpha = this.alpha;
        }
        this.alpha = 1;
    }
    
    /** @private */
	@:allow(com.catalystapps.gaf)
    private function __debugLowlight() : Void
    {
        if (Math.isNaN(this.__debugOriginalAlpha))
        {
            this.__debugOriginalAlpha = this.alpha;
        }
        this.alpha = .05;
    }
    
    /** @private */
	@:allow(com.catalystapps.gaf)
    private function __debugResetLight() : Void
    {
        if (!Math.isNaN(this.__debugOriginalAlpha))
        {
            this.alpha = this.__debugOriginalAlpha;
            this.__debugOriginalAlpha = Math.NaN;
        }
    }
    
    final inline private function updateTransformMatrix() : Void
    {
        if (this._orientationChanged)
        {
            this.transformationMatrix = this.transformationMatrix;
            this._orientationChanged = false;
        }
    }
    
    //--------------------------------------------------------------------------
    //
    // OVERRIDDEN METHODS
    //
    //--------------------------------------------------------------------------
    
    /** Removes a child at a certain index. The index positions of any display objects above
     *  the child are decreased by 1. If requested, the child will be disposed right away. */
    override public function removeChildAt(index : Int, dispose : Bool = false) : DisplayObject
    {
        if (dispose)
        {
            var key : String;
            var instanceName : String;
            var child : DisplayObject = this.getChildAt(index);
            if (Std.isOfType(child, IGAFDisplayObject))
            {
                //var id : Int = this._mcVector.indexOf(try cast(child, GAFMovieClip) catch(e:Dynamic) null);
                var id : Int = -1;
				if (Std.isOfType(child, GAFMovieClip))
				{
					id = this._mcVector.indexOf(cast child);
				}
                if (id >= 0)
                {
                    this._mcVector.splice(id, 1);
                }
                //id = this._imagesVector.indexOf(try cast(child, IGAFImage) catch(e:Dynamic) null);
                id = -1;
				if (Std.isOfType(child, IGAFImage))
				{
					id = this._imagesVector.indexOf(cast child);
				}
                if (id >= 0)
                {
                    this._imagesVector.splice(id, 1);
                }
                id = this._displayObjectsVector.indexOf(cast child);
                if (id >= 0)
                {
                    this._displayObjectsVector.splice(id, 1);
                    
                    for (key in this._displayObjectsDictionary.keys())
                    {
                        if (this._displayObjectsDictionary[key] == child)
                        {
                            if (this._config.namedParts != null)
                            {
                                instanceName = this._config.namedParts[key];
                                //if (instanceName != null && Reflect.hasField(this, instanceName))
                                if (instanceName != null && props.exists(instanceName))
                                {
                                    //Reflect.deleteField(this, instanceName);
									props.remove(instanceName);
                                }
                            }
                            
                            _displayObjectsDictionary.remove(key);
                            break;
                        }
                    }
                }
                
                for (key in this._stencilMasksDictionary.keys())
                {
                    if (this._stencilMasksDictionary[key] == child)
                    {
                        if (this._config.namedParts != null)
                        {
                            instanceName = this._config.namedParts[key];
							//if (instanceName != null && Reflect.hasField(this, instanceName))
							if (instanceName != null && props.exists(instanceName))
                            {
                                //Reflect.deleteField(this, instanceName);
								props.remove(instanceName);
                            }
                        }
                        
						this._stencilMasksDictionary.remove(key);
                        break;
                    }
                }
            }
        }
        
        return super.removeChildAt(index, dispose);
    }
    
    /** Returns a child object with a certain name (non-recursively). */
    override public function getChildByName(name : String) : DisplayObject
    {
        var numChildren : Int = this._displayObjectsVector.length;
        for (i in 0...numChildren)
        {
            if (this._displayObjectsVector[i].name == name)
            {
                //return try cast(this._displayObjectsVector[i], DisplayObject) catch(e:Dynamic) null;
                return cast(this._displayObjectsVector[i], DisplayObject);
            }
        }
        
        return super.getChildByName(name);
    }
    
    /**
	 * Disposes all resources of the display object instance. Note: this method won't delete used texture atlases from GPU memory.
	 * To delete texture atlases from GPU memory use <code>unloadFromVideoMemory()</code> method for <code>GAFTimeline</code> instance
	 * from what <code>GAFMovieClip</code> was instantiated.
	 * Call this method every time before delete no longer required instance! Otherwise GPU memory leak may occur!
	 */
    override public function dispose() : Void
    {
        if (this._disposed)
        {
            return;
        }
        this.stop();
        
        if (this._addToJuggler)
        {
            Starling.current.juggler.remove(this);
        }
        
        var i : Int;
        var l : Int = this._displayObjectsVector.length;
        for (i in 0...l)
        {
            this._displayObjectsVector[i].dispose();
        }
        
        for (key in this._stencilMasksDictionary.keys())
        {
            this._stencilMasksDictionary[key].dispose();
        }
        
        if (this._boundsAndPivot != null)
        {
            this._boundsAndPivot.dispose();
            this._boundsAndPivot = null;
        }
        
        this._displayObjectsDictionary = null;
        this._stencilMasksDictionary = null;
        this._displayObjectsVector = null;
        this._imagesVector = null;
        this._gafTimeline = null;
        this._mcVector = null;
        this._config = null;
        
        if (this.parent != null)
        {
            this.removeFromParent();
        }
        super.dispose();
        
        this._disposed = true;
    }
    
    /** @private */
    override public function render(painter : Painter) : Void
    {
        try
        {
            super.render(painter);
        }
        catch (error : Dynamic)
        {
            if (Std.isOfType(error, IllegalOperationError) && (Std.string(error.message)).indexOf("not possible to stack filters") != -1)
            {
                if (this.hasEventListener(ErrorEvent.ERROR))
                {
                    this.dispatchEventWith(ErrorEvent.ERROR, true, error.message);
                }
                else
                {
                    throw error;
                }
            }
            else
            {
                throw error;
            }
        }
    }
    
    /** @private */
    override private function set_pivotX(value : Float) : Float
    {
        this._pivotChanged = true;
        super.pivotX = value;
        return value;
    }
    
    /** @private */
    override private function set_pivotY(value : Float) : Float
    {
        this._pivotChanged = true;
        super.pivotY = value;
        return value;
    }
    
    /** @private */
    override private function get_x() : Float
    {
        updateTransformMatrix();
        return super.x;
    }
    
    /** @private */
    override private function get_y() : Float
    {
        updateTransformMatrix();
        return super.y;
    }
    
    /** @private */
    override private function get_rotation() : Float
    {
        updateTransformMatrix();
        return super.rotation;
    }
    
    /** @private */
    override private function get_scaleX() : Float
    {
        updateTransformMatrix();
        return super.scaleX;
    }
    
    /** @private */
    override private function get_scaleY() : Float
    {
        updateTransformMatrix();
        return super.scaleY;
    }
    
    /** @private */
    override private function get_skewX() : Float
    {
        updateTransformMatrix();
        return super.skewX;
    }
    
    /** @private */
    override private function get_skewY() : Float
    {
        updateTransformMatrix();
        return super.skewY;
    }
    
    //--------------------------------------------------------------------------
    //
    //  EVENT HANDLERS
    //
    //--------------------------------------------------------------------------
    
    private function changeCurrentFrame(isSkipping : Bool) : Void
    {
        this._nextFrame = this._currentFrame + ((this._reverse) ? -1 : 1);
        this._startFrame = ((this._playingSequence != null) ? this._playingSequence.startFrameNo : 1) - 1;
        this._finalFrame = ((this._playingSequence != null) ? this._playingSequence.endFrameNo : this._totalFrames) - 1;
        
		var resetInvisibleChildren : Bool = false;
		
        if ((this._nextFrame >= this._startFrame) && (this._nextFrame <= this._finalFrame))
        {
            this._currentFrame = this._nextFrame;
            this._lastFrameTime += this._frameDuration;
        }
        else if (!this._loop)
        {
            this.stop();
        }
        else
        {
            this._currentFrame = (this._reverse) ? this._finalFrame : this._startFrame;
            this._lastFrameTime += this._frameDuration;
            resetInvisibleChildren = true;
        }
        
        this.runActions();
        
        //actions may interrupt playback and lead to content disposition
        if (this._disposed)
        {
            return;
        }
        else if (this._config.disposed)
        {
            this.dispose();
            return;
        }
        
        if (!isSkipping)
		{
			// Draw will trigger events if any
            this.draw();
        }
        else
        {
            this.checkPlaybackEvents();
        }
        
        if (resetInvisibleChildren) 
		{
			//reset timelines that aren't visible
            var i : Int = this._mcVector.length;
            while (i-- > 0)
            {
                if (this._mcVector[i]._hidden)
                {
                    this._mcVector[i].reset();
                }
            }
        }
    }
    
    //--------------------------------------------------------------------------
    //
    //  GETTERS AND SETTERS
    //
    //--------------------------------------------------------------------------
    
    /**
	 * Specifies the number of the frame in which the playhead is located in the timeline of the GAFMovieClip instance. First frame is "1"
	 */
    private function get_currentFrame() : Int
    {
        return (this._currentFrame + 1);
    }
    
    /**
	 * The total number of frames in the GAFMovieClip instance.
	 */
    private function get_totalFrames() : Int
    {
        return this._totalFrames;
    }
    
    /**
	 * Indicates whether GAFMovieClip instance already in play
	 */
    private function get_inPlay() : Bool
    {
        return this._inPlay;
    }
    
    /**
	 * Indicates whether GAFMovieClip instance continue playing from start frame after playback reached animation end
	 */
    private function get_loop() : Bool
    {
        return this._loop;
    }
    
    private function set_loop(loop : Bool) : Bool
    {
        this._loop = loop;
        return loop;
    }
    
    /**
	 * The smoothing filter that is used for the texture. Possible values are <code>TextureSmoothing.BILINEAR, TextureSmoothing.NONE, TextureSmoothing.TRILINEAR</code>
	 */
    private function set_smoothing(value : String) : String
    {
        if (TextureSmoothing.isValid(value))
        {
            this._smoothing = value;
            
            var i : Int = this._imagesVector.length;
            while (i-- > 0)
            {
                this._imagesVector[i].textureSmoothing = this._smoothing;
            }
        }
        return value;
    }
    
    private function get_smoothing() : String
    {
        return this._smoothing;
    }
    
    private function get_useClipping() : Bool
    {
        return this._useClipping;
    }
    
    /** @private */
    private function get_maxSize() : Point
    {
        return this._maxSize;
    }
    
    /** @private */
    private function set_maxSize(value : Point) : Point
    {
        this._maxSize = value;
        return value;
    }
    
    /**
	 * if set <code>true</code> - <code>GAFMivieclip</code> will be clipped with flash stage dimensions
	 */
    private function set_useClipping(value : Bool) : Bool
    {
        this._useClipping = value;
        
        if (this._useClipping && this._config.stageConfig != null)
        {
            this.mask = new Quad(this._config.stageConfig.width * this._scale, this._config.stageConfig.height * this._scale);
        }
        else
        {
            this.mask = null;
        }
        return value;
    }
    
    private function get_fps() : Float
    {
        if (this._frameDuration == Math.POSITIVE_INFINITY)
        {
            return 0;
        }
        return 1 / this._frameDuration;
    }
    
    /**
	 * Sets an individual frame rate for <code>GAFMovieClip</code>. If this value is lower than stage fps -  the <code>GAFMovieClip</code> will skip frames.
	 */
    private function set_fps(value : Float) : Float
    {
        if (value <= 0)
        {
            this._frameDuration = Math.POSITIVE_INFINITY;
        }
        else
        {
            this._frameDuration = 1 / value;
        }
        
        var i : Int = this._mcVector.length;
        while (i-- > 0)
        {
            this._mcVector[i].fps = value;
        }
        return value;
    }
    
    private function get_reverse() : Bool
    {
        return this._reverse;
    }
    
    /**
	 * If <code>true</code> animation will be playing in reverse mode
	 */
    private function set_reverse(value : Bool) : Bool
    {
        this._reverse = value;
        
        var i : Int = this._mcVector.length;
        while (i-- > 0)
        {
            this._mcVector[i]._reverse = value;
        }
        return value;
    }
    
    private function get_skipFrames() : Bool
    {
        return this._skipFrames;
    }
    
    /**
	 * Indicates whether GAFMovieClip instance should skip frames when application fps drops down or play every frame not depending on application fps.
	 * Value false will force GAFMovieClip to play each frame not depending on application fps (the same behavior as in regular Flash Movie Clip).
	 * Value true will force GAFMovieClip to play animation "in time". And when application fps drops down it will start skipping frames (default behavior).
	 */
    private function set_skipFrames(value : Bool) : Bool
    {
        this._skipFrames = value;
        
        var i : Int = this._mcVector.length;
        while (i-- > 0)
        {
            this._mcVector[i]._skipFrames = value;
        }
        return value;
    }
    
    /** @private */
    private function get_pivotMatrix() : Matrix
    {
		//HELPER_MATRIX.copyFrom(this._pivotMatrix);
        HELPER_MATRIX.identity();
        
        if (this._pivotChanged)
        {
            HELPER_MATRIX.tx = this.pivotX;
            HELPER_MATRIX.ty = this.pivotY;
        }
        
        return HELPER_MATRIX;
    }
    
    //--------------------------------------------------------------------------
    //
    //  STATIC METHODS
    //
    //--------------------------------------------------------------------------
    
	extern inline
    private static function getTransformMatrix(displayObject : IGAFDisplayObject, matrix : Matrix) : Matrix
    {
        matrix.copyFrom(displayObject.pivotMatrix);
        
        return matrix;
    }
	
	
	//dynamic replace
	public function get(name:String):DisplayObject
	{
		return props.get(name);
	}
}
