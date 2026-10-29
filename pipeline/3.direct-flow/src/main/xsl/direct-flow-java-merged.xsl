<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:map="http://www.w3.org/2005/xpath-functions/map"
                xmlns:f="urn:direct-flow-java"
                exclude-result-prefixes="xs f map"
                expand-text="yes">

    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:function name="f:package-part" as="xs:string">
        <xsl:param name="class" as="xs:string"/>
        <xsl:sequence select="
            if (starts-with($class, '__unresolved__.') or not(contains($class, '.'))) then ''
            else replace($class, '\.[^.]+$', '')
        "/>
    </xsl:function>

    <xsl:function name="f:simple-name" as="xs:string">
        <xsl:param name="class" as="xs:string"/>
        <xsl:sequence select="if (contains($class, '.')) then replace($class, '^.*\.', '') else $class"/>
    </xsl:function>

    <xsl:function name="f:package-prefix-base" as="xs:string">
        <xsl:param name="package" as="xs:string"/>
        <xsl:variable name="letters" as="xs:string*"
                      select="tokenize($package, '\.') ! substring(., 1, 1)"/>
        <xsl:variable name="base" as="xs:string" select="lower-case(string-join($letters, ''))"/>
        <xsl:sequence select="if ($base = '') then 'p' else $base"/>
    </xsl:function>

    <xsl:function name="f:next-free-prefix" as="xs:string">
        <xsl:param name="base" as="xs:string"/>
        <xsl:param name="used-prefixes" as="xs:string*"/>
        <xsl:param name="index" as="xs:integer"/>
        <xsl:variable name="candidate" as="xs:string" select="if ($index = 0) then $base else concat($base, $index)"/>
        <xsl:sequence select="
            if ($candidate = ''
                or $candidate = $used-prefixes
                or starts-with($candidate, 'xml'))
            then f:next-free-prefix($base, $used-prefixes, $index + 1)
            else $candidate
        "/>
    </xsl:function>

    <xsl:function name="f:compact-class" as="xs:string">
        <xsl:param name="class" as="xs:string"/>
        <xsl:param name="package-prefix-map" as="map(xs:string, xs:string)"/>
        <xsl:variable name="pkg" as="xs:string" select="f:package-part($class)"/>
        <xsl:variable name="prefix" as="xs:string?" select="map:get($package-prefix-map, $pkg)"/>
        <xsl:sequence select="
            if ($pkg = '' or starts-with($class, '__unresolved__.')) then $class
            else if (exists($prefix)) then concat($prefix, ':', f:simple-name($class))
            else $class
        "/>
    </xsl:function>

    <xsl:template match="/flow-graph-merged">
        <xsl:variable name="allClasses" as="xs:string*"
                      select="for $v in (edges/edge/@source, edges/edge/@target) return normalize-space($v)"/>
        <xsl:variable name="packages" as="xs:string*">
            <xsl:for-each-group select="$allClasses[not(starts-with(., '__unresolved__.')) and contains(., '.')]"
                                group-by="replace(., '\.[^.]+$', '')">
                <xsl:sort select="current-grouping-key()"/>
                <xsl:sequence select="current-grouping-key()"/>
            </xsl:for-each-group>
        </xsl:variable>
        <xsl:variable name="reserved-prefixes" as="xs:string*"
                      select="('xml', 'xmlns', 'xsl', 'xs', 'fn', 'l', 'm', 'r')"/>
        <xsl:variable name="package-prefix-map" as="map(xs:string, xs:string)">
            <xsl:iterate select="$packages">
                <xsl:param name="used-prefixes" as="xs:string*" select="$reserved-prefixes"/>
                <xsl:param name="entries" as="map(xs:string, xs:string)*" select="()"/>
                <xsl:on-completion select="map:merge($entries)"/>
                <xsl:variable name="pkg" as="xs:string" select="."/>
                <xsl:variable name="base" as="xs:string" select="f:package-prefix-base($pkg)"/>
                <xsl:variable name="prefix" as="xs:string" select="f:next-free-prefix($base, $used-prefixes, 0)"/>
                <xsl:next-iteration>
                    <xsl:with-param name="used-prefixes" select="($used-prefixes, $prefix)"/>
                    <xsl:with-param name="entries" select="($entries, map:entry($pkg, $prefix))"/>
                </xsl:next-iteration>
            </xsl:iterate>
        </xsl:variable>
        <direct-flows language="java">
            <java-namespaces>
                <xsl:for-each select="$packages">
                    <namespace prefix="{map:get($package-prefix-map, .)}" package="{.}"/>
                </xsl:for-each>
            </java-namespaces>
            <xsl:for-each select="edges/edge">
                <xsl:variable name="op" as="xs:string"
                              select="if (@kind = 'instantiates') then 'instantiates' else 'invokes'"/>
                <xsl:variable name="sourceFqn" as="xs:string" select="normalize-space(@source)"/>
                <xsl:variable name="targetFqn" as="xs:string" select="normalize-space(@target)"/>
                <xsl:variable name="source" as="xs:string" select="f:compact-class($sourceFqn, $package-prefix-map)"/>
                <xsl:variable name="target" as="xs:string" select="f:compact-class($targetFqn, $package-prefix-map)"/>
                <xsl:if test="$source ne '' and $target ne ''">
                    <xsl:variable name="method" as="xs:string" select="normalize-space(@method)"/>
                    <xsl:variable name="via" as="xs:string" select="normalize-space(@via)"/>
                    <xsl:variable name="id" as="xs:string" select="concat('java|', $op, '|', $source, '|', $target, '|', $method, '|', $via)"/>
                    <xsl:variable name="lineRefs" as="xs:string*" select="distinct-values(lines/line/@n[normalize-space(.) ne '']) ! normalize-space(.)"/>
                    <xsl:variable name="evidenceRefs" as="xs:string*">
                        <xsl:for-each select="distinct-values(sources/source/@file[normalize-space(.) ne ''] ! normalize-space(.))">
                            <xsl:variable name="fileRef" as="xs:string" select="normalize-space(.)"/>
                            <xsl:choose>
                                <xsl:when test="exists($lineRefs)">
                                    <xsl:for-each select="$lineRefs">
                                        <xsl:sort select="number(.)" data-type="number"/>
                                        <xsl:sequence select="concat($fileRef, '#L', .)"/>
                                    </xsl:for-each>
                                </xsl:when>
                                <xsl:otherwise>
                                    <xsl:sequence select="$fileRef"/>
                                </xsl:otherwise>
                            </xsl:choose>
                        </xsl:for-each>
                    </xsl:variable>
                    <direct-flow id="{$id}"
                                 source="{$source}"
                                 target="{$target}"
                                 operation="{$op}"
                                 language="java"
                                 derivation-rule="java.expression.flow"
                                 resolution-status="{if (starts-with($targetFqn, '__unresolved__.')) then 'UNRESOLVED' else 'PROVEN'}">
                        <xsl:for-each-group select="$evidenceRefs" group-by=".">
                            <xsl:sort select="current-grouping-key()"/>
                            <evidence ref="{current-grouping-key()}"/>
                        </xsl:for-each-group>
                        <xsl:if test="empty($evidenceRefs)">
                            <evidence ref="{$id}"/>
                        </xsl:if>
                    </direct-flow>
                </xsl:if>
            </xsl:for-each>
        </direct-flows>
    </xsl:template>

</xsl:stylesheet>
